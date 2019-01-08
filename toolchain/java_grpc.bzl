JavaGrpcInfo = provider(
    fields = {
        "deps": "",
        "runtime_deps": "",
        "exports": "",
        "protoc": "",
        "protoc_lite_plugin": "",
        "protoc_grpc_plugin": "",
        "compile": "",
        "flavor": "",
    },
)

def _compile(ctx, toolchain = None, deps = []):
    """
    """
    wtf = java_common.JavaRuntimeInfo
    fail(wtf)

    # compile ProtoInfo.direct_sources + ProtoInfo.transitive_descriptor_sets
    # - to a java(lite?) src jar
    # - to a grpc(lite?) src jar

    java_srcs = ctx.actions.declare_file("")
    grpc_srcs = ctx.actions.declare_file("")
    compiled_jar = ctx.actions.declare_file("")

    java_info = java_common.compile(
        ctx,
        source_jars = [java_srcs, grpc_srcs],
        deps = toolchain.deps + deps,
        output = compiled_jar,
    )
    return java_info

# java_common.compile(ctx, source_jars = [java-sources.jar, grpc-sources.jar], deps=deps+toolchain_deps
# java_common.create_provider(ctx.actions,

def _grpc_java_toolchain_impl(ctx):
    tc_info = platform_common.ToolchainInfo(
        grpcinfo = JavaGrpcInfo(
            flavor = ctx.attr.flavor,
            deps = ctx.attr.deps,
            runtime_deps = ctx.attr.runtime_deps,
            exports = ctx.attr.exports,
            protoc = ctx.attr.protoc,
            protoc_lite_plugin = ctx.attr.protoc_lite_plugin,
            protoc_grpc_plugin = ctx.attr.protoc_grpc_plugin,
            compile = _compile,
        ),
    )
    return tc_info

grpc_java_toolchain = rule(
    _grpc_java_toolchain_impl,
    attrs = {
        "flavor": attr.string(values = ["normal", "lite"]),
        "runtime_deps": attr.label_list(default = [], providers = [JavaInfo]),
        "deps": attr.label_list(default = [], providers = [JavaInfo]),
        "exports": attr.label_list(default = [], providers = [JavaInfo]),
        "protoc": attr.label(
            executable = True,
            cfg = "host",
        ),
        "protoc_lite_plugin": attr.label(
            mandatory = False,
            executable = True,
            cfg = "host",
        ),
        "protoc_grpc_plugin": attr.label(
            executable = True,
            cfg = "host",
        ),
    },
)

def grpc_java_register_toolchains():
    repo = "@io_grpc_grpc_java"

    #    native.register_toolchains("@io_grpc_grpc_java//toolchain:all")
    native.register_toolchains(
        repo + "//toolchain:normal_android_toolchain",
        repo + "//toolchain:lite_android_toolchain",
        repo + "//toolchain:normal_default_toolchain",
        repo + "//toolchain:lite_default_toolchain",
    )
