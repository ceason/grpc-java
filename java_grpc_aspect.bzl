# java_grpc_library, java_grpc_lite_library, java_grpc_nano_library(?)

# runtime dep
# - toolchain for android pulls in 'okhttp'
# - default toolchain pulls in netty (maybe add shaded netty?)

_TOOLCHAINS = {
    flavor: "@io_grpc_grpc_java//toolchain:%s_toolchain_type" % flavor
    for flavor in ["lite", "normal"]
}

_GeneratedFiles = provider(
    fields = {
        "jars": "Depset<File> of compiled jars",
    },
)

def _aspect_impl(target, ctx):
    # proto_info = target[ProtoInfo] # <- update provider when ProtoInfo is a real thing
    proto_info = target.proto

    transitive_jars = []
    for dep in ctx.rule.attr.deps:
        transitive_jars += [dep[_GeneratedFiles].jars]

    if len(proto_info.direct_sources) > 0:
        tc = ctx.toolchains[ctx.attr._toolchain].grpcinfo
        java_info, jar = tc.compile(
            ctx,
            toolchain = tc,
            proto_info = proto_info,
            deps = ctx.rule.attr.deps,
        )
        return [java_info, _GeneratedFiles(
            jars = depset(direct = [jar], transitive = transitive_jars),
        )]
    else:
        java_info = java_common.merge([
            dep[JavaInfo]
            for dep in ctx.rule.attr.deps
        ])
        return [java_info, _GeneratedFiles(
            jars = depset(transitive = transitive_jars),
        )]

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
            files = depset(transitive = [
                dep[_GeneratedFiles].jars
                for dep in ctx.attr.deps
            ]),
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
