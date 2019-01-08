# java_grpc_library, java_grpc_lite_library, java_grpc_nano_library(?)

# runtime dep
# - toolchain for android pulls in 'okhttp'
# - default toolchain pulls in netty (maybe add shaded netty?)

_TOOLCHAINS = {
    flavor: "@io_grpc_grpc_java//toolchain:%s_toolchain_type" % flavor
    for flavor in ["lite", "normal"]
}

_aspect_aggregated_stuff = provider(
    fields = {
        "java_infos": "depset of JavaInfos",
    },
)

def _aspect_impl(target, ctx):
    tc = ctx.toolchains[ctx.attr._toolchain].grpcinfo
    proto_info = target.proto
    # proto_info = target[ProtoInfo] # <- update provider when ProtoInfo is a real thing

    transitive = []
    if _aspect_aggregated_stuff in target:
        transitive += [target[_aspect_aggregated_stuff].java_infos]
    java_info = tc.compile(
        ctx,
        toolchain = tc,
        proto_info = proto_info,
    )
    return [_aspect_aggregated_stuff(
        java_infos = depset(
            direct = [java_info],
            transitive = transitive,
        ),
    )]

def _java_grpc_library_impl(ctx):
    """
    """
    transitive = []
    for dep in ctx.attr.deps:
        transitive += [dep[_aspect_aggregated_stuff].java_infos]

    le_java_info = java_common.merge(depset(transitive = transitive).to_list())
    print(le_java_info)
    return [
        le_java_info,
        DefaultInfo(
            files = le_java_info.full_compile_jars,
        ),
    ]

_lite_aspect = aspect(
    _aspect_impl,
    toolchains = [_TOOLCHAINS["lite"]],
    attr_aspects = ["deps"],
    fragments = ["java"],
    attrs = {"_toolchain": attr.string(default = _TOOLCHAINS["lite"])},
)

_normal_aspect = aspect(
    _aspect_impl,
    toolchains = [_TOOLCHAINS["normal"]],
    attr_aspects = ["deps"],
    fragments = ["java"],
    attrs = {"_toolchain": attr.string(default = _TOOLCHAINS["normal"])},
)

java_grpc_library = rule(
    _java_grpc_library_impl,
    toolchains = [_TOOLCHAINS["normal"]],
    attrs = {
        "_toolchain": attr.string(default = _TOOLCHAINS["normal"]),
        "deps": attr.label_list(
            mandatory = True,
            providers = ["proto"],
            aspects = [_normal_aspect],
        ),
    },
)

java_lite_grpc_library = rule(
    _java_grpc_library_impl,
    toolchains = [_TOOLCHAINS["lite"]],
    attrs = {
        "_toolchain": attr.string(default = _TOOLCHAINS["lite"]),
        "deps": attr.label_list(
            mandatory = True,
            providers = ["proto"],
            aspects = [_lite_aspect],
        ),
    },
)
