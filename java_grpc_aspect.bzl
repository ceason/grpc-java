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

    # get our java_info, and possibly a new jar too
    java_info = None
    direct_jars = []
    if len(proto_info.direct_sources) > 0:
        tc = ctx.toolchains[ctx.attr._toolchain].grpcinfo
        java_info, jar = tc.compile(
            ctx,
            toolchain = tc,
            proto_info = proto_info,
            deps = ctx.rule.attr.deps,
        )
        direct_jars += [jar]
    else:
        java_info = java_common.merge([
            dep[JavaInfo]
            for dep in ctx.rule.attr.deps
        ])

    # accumulate aspect-generated files
    genfiles = _GeneratedFiles(
        jars = depset(
            direct = direct_jars,
            transitive = [
                dep[_GeneratedFiles].jars
                for dep in ctx.rule.attr.deps
            ],
        ),
    )

    # additionally return legacy provider so IntelliJ plugin is happy :-\
    return struct(
        proto_java = java_info,
        providers = [java_info, genfiles],
    )

_normal_aspect = aspect(
    _aspect_impl,
    toolchains = [_TOOLCHAINS["normal"]],
    attr_aspects = ["deps"],
    fragments = ["java"],
    provides = ["proto_java"],
    attrs = {"_toolchain": attr.string(default = _TOOLCHAINS["normal"])},
)

_lite_aspect = aspect(
    _aspect_impl,
    toolchains = [_TOOLCHAINS["lite"]],
    attr_aspects = ["deps"],
    fragments = ["java"],
    provides = ["proto_java"],
    attrs = {"_toolchain": attr.string(default = _TOOLCHAINS["lite"])},
)

def _java_grpc_library_impl(ctx):
    tc = ctx.toolchains[ctx.attr._toolchain].grpcinfo
    java_info = java_common.merge([
        dep[JavaInfo]
        for dep in ctx.attr.deps + tc.exports
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
