# java_grpc_library, java_grpc_lite_library, java_grpc_nano_library(?)

# runtime dep
# - toolchain for android pulls in 'okhttp'
# - default toolchain pulls in netty (maybe add shaded netty?)

_TOOLCHAINS = {
    flavor: "@io_grpc_grpc_java//toolchain:%s_toolchain_type" % flavor
    for flavor in ["lite", "normal"]
}

def _aspect_impl(target, ctx):
    print(target)
    print(ctx)
    fail("asdfbbq")

def _java_grpc_library_impl(ctx):
    """
    """
    tc = ctx.toolchains[ctx.attr._toolchain]

#_ASPECTS = {flavor.name: aspect(
#    _aspect_impl,
#    toolchains = [flavor.toolchain],
#    attr_aspects = ["deps"],
#    attrs = {
#        "_toolchain": attr.string(default = flavor.toolchain),
#    },
#) for flavor in _FLAVORS}

_lite_aspect = aspect(
    _aspect_impl,
    toolchains = [_TOOLCHAINS["lite"]],
    attr_aspects = ["deps"],
    attrs = {"_toolchain": attr.string(default = _TOOLCHAINS["lite"])},
)

_normal_aspect = aspect(
    _aspect_impl,
    toolchains = [_TOOLCHAINS["normal"]],
    attr_aspects = ["deps"],
    attrs = {"_toolchain": attr.string(default = _TOOLCHAINS["normal"])},
)

#_RULES = {flavor.name: rule(
#    _java_grpc_library_impl,
#    toolchains = [flavor.toolchain],
#    attrs = {
#        "_toolchain": attr.string(default = flavor.toolchain),
#        "deps": attr.label_list(
#            mandatory = True,
#            providers = ["proto"],
#            aspects = [_ASPECTS[flavor.name]],
#        ),
#    },
#) for flavor in _FLAVORS}

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
