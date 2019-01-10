load(
    ":compiler.bzl",
    _GrpcAspectInfo = "GrpcAspectInfo",
    _java_grpc_aspect = "java_grpc_aspect",
    _java_lite_grpc_aspect = "java_lite_grpc_aspect",
)

def _rule_impl(ctx):
    # exports come from the aspect's compiler, are the same for all deps
    # so we only need to grab one
    exports = ctx.attr.deps[0][_GrpcAspectInfo].exports

    # Combine generated & configured jars
    java_info = java_common.merge([
        dep[JavaInfo]
        for dep in ctx.attr.deps + exports + ctx.attr.transport
    ])
    return [
        java_info,
        DefaultInfo(
            files = depset(transitive = [
                dep[_GrpcAspectInfo].jars
                for dep in ctx.attr.deps
            ]),
            runfiles = ctx.runfiles(files = java_info.transitive_runtime_jars.to_list()),
        ),
    ]

def _rule_attrs(aspect_):
    return {
        "deps": attr.label_list(
            providers = ["proto"],
            aspects = [aspect_],
            mandatory = True,
        ),
        "transport": attr.label_list(
            providers = [JavaInfo],
            default = ["//java_grpc_library:platform_default_transport"],
        ),
    }

java_grpc_library = rule(
    _rule_impl,
    attrs = _rule_attrs(_java_grpc_aspect),
    provides = [JavaInfo],
)

java_lite_grpc_library = rule(
    _rule_impl,
    attrs = _rule_attrs(_java_lite_grpc_aspect),
    provides = [JavaInfo],
)
