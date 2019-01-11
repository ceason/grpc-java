GrpcAspectInfo = provider(
    fields = {
        "exports": "List of JavaInfo targets to export from the consuming rule",
        "jars": "Depset<File> of compiled jars",
    },
)

GrpcProtoCompiler = provider()

_compiler_attrs = {
    "deps": attr.label_list(default = [], providers = [JavaInfo]),
    "exports": attr.label_list(default = [], providers = [JavaInfo]),
    "protoc": attr.label(
        executable = True,
        cfg = "host",
        default = Label("@com_google_protobuf//:protoc"),
    ),
    "java_plugin": attr.label(
        executable = True,
        cfg = "host",
        default = None,
    ),
    "grpc_plugin": attr.label(
        executable = True,
        cfg = "host",
        default = Label("//compiler:grpc_java_plugin"),
    ),
    "grpc_plugin_opts": attr.string_list(default = []),
    "java_plugin_opts": attr.string_list(default = []),
    "_java_toolchain": attr.label(
        default = Label("@bazel_tools//tools/jdk:toolchain"),
        cfg = "host",
    ),
    "_host_javabase": attr.label(
        default = Label("@bazel_tools//tools/jdk:current_java_runtime"),
        cfg = "host",
    ),
}

def _grpc_proto_compiler_impl(ctx):
    # Pass configured attrs through via provider
    return [GrpcProtoCompiler(
        path_fragment = ctx.attr.name,
        **{k: getattr(ctx.attr, k) for k in _compiler_attrs.keys()}
    )]

grpc_proto_compiler = rule(
    _grpc_proto_compiler_impl,
    attrs = _compiler_attrs,
)

def _aspect_impl(target, ctx):
    # proto_info = target[ProtoInfo] # <- update provider when ProtoInfo is a real thing
    proto_info = target.proto
    compiler = ctx.attr._compiler[GrpcProtoCompiler]

    # return (and merge) transitive deps if there are no sources to compile
    if len(proto_info.direct_sources) == 0:
        java_info = java_common.merge([dep[JavaInfo] for dep in ctx.rule.attr.deps])
        return struct(
            proto_java = java_info,
            providers = [java_info, GrpcAspectInfo(
                exports = compiler.exports,
                jars = depset(transitive = [
                    dep[GrpcAspectInfo].jars
                    for dep in ctx.rule.attr.deps
                ]),
            )],
        )

    java_srcs = ctx.actions.declare_file("%s/%s-java-sources.jar" % (compiler.path_fragment, ctx.rule.attr.name))
    grpc_srcs = ctx.actions.declare_file("%s/%s-grpc-sources.jar" % (compiler.path_fragment, ctx.rule.attr.name))
    compiled_jar = ctx.actions.declare_file("%s/%s.jar" % (compiler.path_fragment, ctx.rule.attr.name))

    descriptors = depset(
        direct = [proto_info.direct_descriptor_set],
        transitive = [proto_info.transitive_descriptor_sets],
    )
    protoc = compiler.protoc.files_to_run.executable
    grpc_plugin = compiler.grpc_plugin.files_to_run.executable
    java_plugin = compiler.java_plugin.files_to_run.executable if compiler.java_plugin else None

    # generate java & grpc srcs
    args = ctx.actions.args()
    args.add_joined("--descriptor_set_in", descriptors, join_with = ":", omit_if_empty = True)
    args.add("--plugin=protoc-gen-grpc-java=%s" % grpc_plugin.path)
    args.add("--grpc-java_out={opts}:{file}".format(
        opts = ",".join(compiler.grpc_plugin_opts),
        file = grpc_srcs.path,
    ))
    if java_plugin:
        args.add("--plugin=protoc-gen-javaplugin=%s" % java_plugin.path)
        args.add("--javaplugin_out={opts}:{file}".format(
            opts = ",".join(compiler.java_plugin_opts),
            file = java_srcs.path,
        ))
    else:
        args.add("--java_out={opts}:{file}".format(
            opts = ",".join(compiler.java_plugin_opts),
            file = java_srcs.path,
        ))

    # TODO: figure out how to handle import_prefix,proto_source_root,strip_import_prefix
    args.add_all(proto_info.direct_sources)

    # run the action
    # merge the srcjars
    # compile the merged jar
    ctx.actions.run(
        inputs = descriptors,
        outputs = [java_srcs, grpc_srcs],
        executable = protoc,
        arguments = [args],
        tools = [
            grpc_plugin,
        ] + ([java_plugin] if java_plugin else []),
    )
    sources_jar = java_common.pack_sources(
        ctx.actions,
        output_jar = compiled_jar,
        source_jars = [grpc_srcs, java_srcs],
        java_toolchain = compiler._java_toolchain,
        host_javabase = compiler._host_javabase,
    )
    compile_deps = [
        dep[JavaInfo]
        for dep in compiler.deps + ctx.rule.attr.deps
    ]
    java_common.compile(
        ctx,
        source_jars = [sources_jar],
        deps = compile_deps,
        output = compiled_jar,
        java_toolchain = compiler._java_toolchain,
        host_javabase = compiler._host_javabase,
    )

    # construct the providers:
    # - JavaInfo
    # - GrpcAspectInfo
    java_info = JavaInfo(
        output_jar = compiled_jar,
        compile_jar = compiled_jar,
        source_jar = sources_jar,
        deps = compile_deps,
    )
    return struct(
        # additionally return legacy provider so IntelliJ plugin is happy :-\
        proto_java = java_info,
        providers = [java_info, GrpcAspectInfo(
            exports = compiler.exports,
            jars = depset(
                direct = [compiled_jar],
                transitive = [
                    dep[GrpcAspectInfo].jars
                    for dep in ctx.rule.attr.deps
                ],
            ),
        )],
    )



java_grpc_aspect = aspect(
    _aspect_impl,
    attr_aspects = ["deps"],
    fragments = ["java"],
    provides = ["proto_java", JavaInfo],
    attrs = {
        "_compiler": attr.label(
            providers = [GrpcProtoCompiler],
            default = Label("//java_grpc_library:grpc_java"),
        ),
    },
)

java_lite_grpc_aspect = aspect(
    _aspect_impl,
    attr_aspects = ["deps"],
    fragments = ["java"],
    provides = ["proto_java", JavaInfo],
    attrs = {
        "_compiler": attr.label(
            providers = [GrpcProtoCompiler],
            default = Label("//java_grpc_library:grpc_javalite"),
        ),
    },
)
