# java_grpc_library, java_grpc_lite_library, java_grpc_nano_library(?)

# runtime dep
# - toolchain for android pulls in 'okhttp'
# - default toolchain pulls in netty (maybe add shaded netty?)


def _java_grpc_library_impl():
    """
    """
    tc = ctx.toolchains["//toolchain:toolchain_type"]


java_grpc_library = rule(
    _java_grpc_library_impl,
    attrs = {
        "deps": attr.label_list(mandatory = True, providers = [ProtoInfo]),
    },
    toolchains = ["//toolchain:toolchain_type"],
)

