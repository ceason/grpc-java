def _java_grpc_toolchain_impl(ctx):
    # compute: protoc_java_opts,protoc_grpc_opts
    pass
#    toolchain_info = platform_common.ToolchainInfo(
#        barcinfo = BarcInfo(
#            compiler_path = ctx.attr.compiler_path,
#            system_lib = ctx.attr.system_lib,
#            arch_flags = ctx.attr.arch_flags,
#        ),
#    )
#    return [toolchain_info]


java_grpc_toolchain = rule(
    _java_grpc_toolchain_impl,
    attrs = {
        "flavor": attr.string(values=["normal","lite"]),
#        "protoc_java_opts": attr.string_list(),
#        "protoc_grpc_opts": attr.string_list(),
        "runtime_deps": attr.label_list(default = []),
        "deps": attr.label_list(default = []),
        "exports": attr.label_list(default = []),
        "protoc": attr.label(
            executable = True,
            cfg = "host",
        ),
        "protoc_grpc_plugin": attr.label(
            executable = True,
            cfg = "host",
        ),
    },
)
