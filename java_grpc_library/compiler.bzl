GrpcAspectInfo = provider(
    fields = {
        "exports": "List of JavaInfo targets to export from the consuming rule",
        "jars": "Depset<File> of compiled jars",
    },
)

_GrpcProtoCompiler = provider()

def _grpc_proto_compiler_impl(ctx):
    # Pass configured attrs through via provider
    return [_GrpcProtoCompiler(attr = ctx.attr)]

grpc_proto_compiler = rule(
    _grpc_proto_compiler_impl,
    attrs = {
        "deps": attr.label_list(default = [], providers = [JavaInfo]),
        "exports": attr.label_list(default = [], providers = [JavaInfo]),
        "protoc": attr.label(
            executable = True,
            cfg = "host",
            default = "@com_google_protobuf//:protoc",
        ),
        "java_plugin": attr.label(
            executable = True,
            cfg = "host",
            default = None,
        ),
        "grpc_plugin": attr.label(
            executable = True,
            cfg = "host",
            default = "//compiler:grpc_java_plugin",
        ),
        "grpc_plugin_opts": attr.string_list(default = []),
        "java_plugin_opts": attr.string_list(default = []),
        "_java_toolchain": attr.label(default = Label("@bazel_tools//tools/jdk:toolchain")),
        "_host_javabase": attr.label(default = Label("@bazel_tools//tools/jdk:current_java_runtime")),
    },
)

def _aspect_impl(target, ctx):
    # proto_info = target[ProtoInfo] # <- update provider when ProtoInfo is a real thing
    proto_info = target.proto
    compiler = ctx.attr._compiler[_GrpcProtoCompiler].attr

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

    output_path_fragment = compiler.name
    java_srcs = ctx.actions.declare_file("%s/%s-java-sources.jar" % (output_path_fragment, ctx.rule.attr.name))
    grpc_srcs = ctx.actions.declare_file("%s/%s-grpc-sources.jar" % (output_path_fragment, ctx.rule.attr.name))
    compiled_jar = ctx.actions.declare_file("%s/%s.jar" % (output_path_fragment, ctx.rule.attr.name))

    descriptors = depset(
        direct = [proto_info.direct_descriptor_set],
        transitive = [proto_info.transitive_descriptor_sets],
    )
    protoc = compiler.protoc.files_to_run.executable
    grpc_plugin = compiler.grpc_plugin.files_to_run.executable
    java_plugin = compiler.java_plugin.files_to_run.executable if compiler.java_plugin else None

    # generate java & grpc srcs
    protoc_inputs = []
    args = ctx.actions.args()
    args.add_joined("--descriptor_set_in", descriptors, join_with = ":", omit_if_empty = True)
    protoc_inputs += [grpc_plugin]
    args.add("--plugin=protoc-gen-grpc-java=%s" % grpc_plugin.path)
    args.add("--grpc-java_out={opts}:{file}".format(
        opts = ",".join(compiler.grpc_plugin_opts),
        file = grpc_plugin.path,
    ))
    if compiler.java_plugin:
        protoc_inputs += [java_plugin]
        args.add("--plugin=protoc-gen-javaplugin=%s" % java_plugin.path)
        args.add("--javaplugin_out={opts}:{file}".format(
            opts = ",".join(compiler.java_plugin_opts),
            file = java_plugin.path,
        ))
    else:
        args.add("--java_out={opts}:{file}".format(
            opts = ",".join(compiler.java_plugin_opts),
            file = java_plugin.path,
        ))

    # TODO:....
    # run the action
    # merge the srcjars
    # compile the merged jar
    # construct the providers:
    # - JavaInfo
    # - GrpcAspectInfo

    # additionally return legacy provider so IntelliJ plugin is happy :-\
    return struct(
        proto_java = java_info,
        providers = [java_info, genfiles],
    )

java_grpc_aspect = aspect(
    _aspect_impl,
    attr_aspects = ["deps"],
    fragments = ["java"],
    provides = ["proto_java", JavaInfo],
    attrs = {
        "_compiler": attr.label(
            providers = [_GrpcProtoCompiler],
            default = "//java_grpc_library:grpc_java",
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
            providers = [_GrpcProtoCompiler],
            default = "//java_grpc_library:grpc_javalite",
        ),
    },
)
