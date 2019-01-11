load(":compiler.bzl", _GrpcProtoCompiler = "GrpcProtoCompiler")

_GrpcAspectInfo = provider(
    fields = {
        "exports": "List of JavaInfo targets to export from the consuming rule",
        "jars": "Depset<File> of compiled jars",
    },
)

def _aspect_impl(target, ctx):
    # proto_info = target[ProtoInfo] # <- update provider when ProtoInfo is a real thing
    proto_info = target.proto
    compiler = ctx.attr._compiler[_GrpcProtoCompiler]

    # return (and merge) transitive deps if there are no sources to compile
    if len(proto_info.direct_sources) == 0:
        java_info = java_common.merge([dep[JavaInfo] for dep in ctx.rule.attr.deps])
        return struct(
            proto_java = java_info,
            providers = [java_info, _GrpcAspectInfo(
                exports = compiler.exports,
                jars = depset(transitive = [
                    dep[_GrpcAspectInfo].jars
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
        providers = [java_info, _GrpcAspectInfo(
            exports = compiler.exports,
            jars = depset(
                direct = [compiled_jar],
                transitive = [
                    dep[_GrpcAspectInfo].jars
                    for dep in ctx.rule.attr.deps
                ],
            ),
        )],
    )

def _grpc_aspect(compiler):
    return {
        "implementation": _aspect_impl,
        "attr_aspects": ["deps"],
        "fragments": ["java"],
        "provides": ["proto_java", JavaInfo],
        "attrs": {
            "_compiler": attr.label(
                providers = [_GrpcProtoCompiler],
                default = Label(compiler),
            ),
        },
    }

def _rule_impl(ctx):
    # exports come from the aspect's compiler, are the same for all deps
    # so we only need to grab one
    exports = ctx.attr.deps[0][_GrpcAspectInfo].exports

    # Combine generated & configured jars
    java_info = java_common.merge([
        dep[JavaInfo]
        for dep in ctx.attr.deps + exports + ctx.attr.transport
    ])
    return struct(
        proto_java = java_info,
        providers = [
            java_info,
            DefaultInfo(
                files = depset(transitive = [dep[_GrpcAspectInfo].jars for dep in ctx.attr.deps]),
                runfiles = ctx.runfiles(files = java_info.transitive_runtime_jars.to_list()),
            ),
        ],
    )

def _grpc_rule(aspect_):
    return rule(
        _rule_impl,
        attrs = {
            "deps": attr.label_list(
                providers = ["proto"],
                aspects = [aspect_],
                mandatory = True,
            ),
            "transport": attr.label_list(
                providers = [JavaInfo],
                default = ["//java_grpc_library:platform_default_transport"],
            ),
        },
        provides = ["proto_java", JavaInfo],
    )

_normal_aspect = aspect(**_grpc_aspect("//java_grpc_library:grpc_java"))
java_grpc_library = _grpc_rule(_normal_aspect)

_lite_aspect = aspect(**_grpc_aspect("//java_grpc_library:grpc_javalite"))
java_lite_grpc_library = _grpc_rule(_lite_aspect)
