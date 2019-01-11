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
