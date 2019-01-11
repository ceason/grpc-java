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
    return struct(
        proto_java = java_info,
        providers = [
            java_info,
            DefaultInfo(
                files = depset(transitive = [dep[_GrpcAspectInfo].jars for dep in ctx.attr.deps]),
                runfiles = ctx.runfiles(files = java_info.transitive_runtime_jars.to_list()),
            ),
        ],
    )

def _grpc_rule(aspect_):
    return rule(
        _rule_impl,
        attrs = {
            "deps": attr.label_list(
                providers = ["proto"],
                aspects = [aspect_],
                mandatory = True,
            ),
            "transport": attr.label_list(
                providers = [JavaInfo],
                default = ["//java_grpc_library:platform_default_transport"],
            ),
        },
        provides = ["proto_java", JavaInfo],
    )

java_grpc_library = _grpc_rule(_java_grpc_aspect)

java_lite_grpc_library = _grpc_rule(_java_lite_grpc_aspect)
