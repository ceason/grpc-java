# java_grpc_library, java_grpc_lite_library, java_grpc_nano_library(?)

# runtime dep
# - toolchain for android pulls in 'okhttp'
# - default toolchain pulls in netty (maybe add shaded netty?)

_TOOLCHAINS = {
    flavor: "@io_grpc_grpc_java//toolchain:%s_toolchain_type" % flavor
    for flavor in ["lite", "normal"]
}

def _aspect_impl(target, ctx):
    proto_info = target.proto

    # proto_info = target[ProtoInfo] # <- update provider when ProtoInfo is a real thing
    if len(proto_info.direct_sources) > 0:
        tc = ctx.toolchains[ctx.attr._toolchain].grpcinfo
        java_info = tc.compile(
            ctx,
            toolchain = tc,
            proto_info = proto_info,
            deps = ctx.rule.attr.deps,
        )
        return [java_info]
    else:
        java_info = java_common.merge([
            dep[JavaInfo]
            for dep in ctx.rule.attr.deps
        ])
        return [java_info]

_normal_aspect = aspect(
    _aspect_impl,
    toolchains = [_TOOLCHAINS["normal"]],
    attr_aspects = ["deps"],
    fragments = ["java"],
    attrs = {"_toolchain": attr.string(default = _TOOLCHAINS["normal"])},
)

_lite_aspect = aspect(
    _aspect_impl,
    toolchains = [_TOOLCHAINS["lite"]],
    attr_aspects = ["deps"],
    fragments = ["java"],
    attrs = {"_toolchain": attr.string(default = _TOOLCHAINS["lite"])},
)

def _java_grpc_library_impl(ctx):
    java_info = java_common.merge([
        dep[JavaInfo]
        for dep in ctx.attr.deps
    ])
    return [
        java_info,
        DefaultInfo(
            files = java_info.full_compile_jars,
            runfiles = ctx.runfiles(files = java_info.transitive_runtime_jars.to_list()),
        ),
    ]

java_grpc_library = rule(
    _java_grpc_library_impl,
    attrs = {
        "deps": attr.label_list(
            mandatory = True,
            providers = ["proto"],
            aspects = [_normal_aspect],
        ),
    },
)

java_lite_grpc_library = rule(
    _java_grpc_library_impl,
    attrs = {
        "deps": attr.label_list(
            mandatory = True,
            providers = ["proto"],
            aspects = [_lite_aspect],
        ),
    },
)
