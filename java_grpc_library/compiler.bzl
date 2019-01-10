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

def _aspect_impl(ctx):
    compiler = ctx.attr._compiler[_GrpcProtoCompiler].attr
    pass

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
