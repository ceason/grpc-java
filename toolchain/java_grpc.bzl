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
        "host_javabase": "",
        "java_toolchain": "",
        "java_runtime": "",
        "output_path": "",
    },
)

def _path_ignoring_repository(f):
    if (len(f.owner.workspace_root) == 0):
        return f.short_path
    return f.path[f.path.find(f.owner.workspace_root) + len(f.owner.workspace_root) + 1:]

def _compile(ctx, toolchain = None, deps = [], proto_info = None):
    """
    deps = <Target>s with JavaInfo. Compiled dependencies
    """

    # find the rule ctx (since this might be invoked from an aspect)
    rule_ctx = ctx
    if hasattr(ctx, "rule"):
        rule_ctx = ctx.rule

    java_srcs = ctx.actions.declare_file("%s/%s-java-sources.jar" % (toolchain.output_path, rule_ctx.attr.name))
    grpc_srcs = ctx.actions.declare_file("%s/%s-grpc-sources.jar" % (toolchain.output_path, rule_ctx.attr.name))
    compiled_jar = ctx.actions.declare_file("%s/%s.jar" % (toolchain.output_path, rule_ctx.attr.name))

    descriptors = depset(
        direct = [proto_info.direct_descriptor_set],
        transitive = [proto_info.transitive_descriptor_sets],
    )

    # generate java & grpc srcs
    protoc = toolchain.protoc.files_to_run.executable
    grpc_plugin = toolchain.protoc_grpc_plugin.files_to_run.executable
    maybe_javalite = []
    proto_args = ctx.actions.args()
    proto_args.add_all("--descriptor_set_in", descriptors)
    proto_args.add("--plugin=protoc-gen-grpc-java=%s" % grpc_plugin.path)
    if toolchain.flavor == "lite":
        javalite = toolchain.protoc_lite_plugin.files_to_run.executable
        maybe_javalite += [javalite]
        proto_args.add("--plugin=protoc-gen-javalite=%s" % javalite.path)
        proto_args.add("--javalite_out=%s" % java_srcs.path)
        proto_args.add("--grpc-java_out=lite:%s" % grpc_srcs.path)
    elif toolchain.flavor == "normal":
        proto_args.add("--java_out=%s" % java_srcs.path)
        proto_args.add("--grpc-java_out=%s" % grpc_srcs.path)
    else:
        fail("Unknown flavor '%s'" % toolchain.flavor)

    # todo: figure out how to handle 'proto_source_root' (ie properly calculate src names)
    proto_args.add_all([_path_ignoring_repository(src) for src in proto_info.direct_sources])
    ctx.actions.run(
        inputs = depset(
            direct = [protoc, grpc_plugin] + maybe_javalite,
            transitive = [descriptors],
        ),
        outputs = [java_srcs, grpc_srcs],
        executable = protoc,
        arguments = [proto_args],
    )

    sources_jar = java_common.pack_sources(
        ctx.actions,
        output_jar = compiled_jar,
        source_jars = [grpc_srcs, java_srcs],
        java_toolchain = toolchain.java_toolchain,
        host_javabase = toolchain.host_javabase,
    )
    compile_deps = [
        dep[JavaInfo]
        for dep in toolchain.deps + deps
    ]
    java_common.compile(
        ctx,
        source_jars = [sources_jar],
        deps = compile_deps,
        output = compiled_jar,
        java_toolchain = toolchain.java_toolchain,
        host_javabase = toolchain.host_javabase,
    )
    java_info = JavaInfo(
        output_jar = compiled_jar,
        compile_jar = compiled_jar,
        source_jar = sources_jar,
        exports = [
            dep[JavaInfo]  # todo: is this right??
            for dep in deps
        ],
        runtime_deps = [
            dep[JavaInfo]
            for dep in toolchain.runtime_deps
        ],
        deps = compile_deps,
    )
    return java_info, compiled_jar

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
            host_javabase = ctx.attr._host_javabase,
            java_toolchain = ctx.attr._java_toolchain,
            java_runtime = ctx.attr._jdk[java_common.JavaRuntimeInfo],
            output_path = "grpc_java_%s" % ctx.attr.flavor,
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
        "_jdk": attr.label(
            default = Label("@bazel_tools//tools/jdk:current_java_runtime"),
            providers = [java_common.JavaRuntimeInfo],
        ),
        "_java_toolchain": attr.label(default = Label("@bazel_tools//tools/jdk:toolchain")),
        "_host_javabase": attr.label(default = Label("@bazel_tools//tools/jdk:current_java_runtime")),
    },
)

def grpc_java_register_toolchains():
    # android toolchains are registered first
    native.register_toolchains(
        "@io_grpc_grpc_java//toolchain:normal_android_toolchain",
        "@io_grpc_grpc_java//toolchain:normal_default_toolchain",
    )
    native.register_toolchains(
        "@io_grpc_grpc_java//toolchain:lite_android_toolchain",
        "@io_grpc_grpc_java//toolchain:lite_default_toolchain",
    )
