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
    """

    tgt_name = ""
    if hasattr(ctx.attr, "name"):
        tgt_name = ctx.attr.name
    else:
        tgt_name = ctx.rule.attr.name

    java_srcs = ctx.actions.declare_file("%s/%s-sources.jar" % (toolchain.output_path, tgt_name))
    grpc_srcs = ctx.actions.declare_file("%s/%s-grpc-sources.jar" % (toolchain.output_path, tgt_name))
    compiled_jar = ctx.actions.declare_file("%s/%s-grpc.jar" % (toolchain.output_path, tgt_name))

    # compile ProtoInfo.direct_sources + ProtoInfo.transitive_descriptor_sets
    # - to a java(lite?) src jar
    # - to a grpc(lite?) src jar

    protoc = toolchain.protoc.files_to_run.executable

    # generate java srcs
    maybe_javalite = []
    proto_args = ctx.actions.args()
    proto_args.add(protoc)
    if toolchain.flavor == "lite":
        javalite = toolchain.protoc_lite_plugin.files_to_run.executable
        maybe_javalite += [javalite]
        proto_args.add("--plugin=protoc-gen-javalite=%s" % javalite.path)
        proto_args.add("--javalite_out=%s" % java_srcs.path)
    else:
        proto_args.add("--java_out=%s" % java_srcs.path)
    proto_args.add_all("--descriptor_set_in", proto_info.transitive_descriptor_sets)
    proto_args.add_all(proto_info.direct_sources)
    ctx.actions.run(
        inputs = depset(
            direct = [protoc] + maybe_javalite + proto_info.direct_sources,
            transitive = [proto_info.transitive_descriptor_sets],
        ),
        outputs = [java_srcs],
        executable = protoc,
        arguments = [proto_args],
    )

    # generate grpc srcs
    grpc_args = ctx.actions.args()
    grpc_args.add(protoc)
    grpc_plugin = toolchain.protoc_grpc_plugin.files_to_run.executable
    grpc_args.add("--plugin=protoc-gen-grpc-java=%s" % grpc_plugin.path)
    if toolchain.flavor == "lite":
        grpc_args.add("--grpc-java_out=lite:%s" % grpc_srcs.path)
    else:
        grpc_args.add("--grpc-java_out=%s" % grpc_srcs.path)
    grpc_args.add_all("--descriptor_set_in", proto_info.transitive_descriptor_sets)
    grpc_args.add_all(proto_info.direct_sources)
    ctx.actions.run(
        inputs = depset(
            direct = [protoc, grpc_plugin] + proto_info.direct_sources,
            transitive = [proto_info.transitive_descriptor_sets],
        ),
        outputs = [grpc_srcs],
        executable = protoc,
        arguments = [grpc_args],
    )

    java_info = java_common.compile(
        ctx,
        source_jars = [java_srcs, grpc_srcs],
        deps = [
            dep[JavaInfo]
            for dep in toolchain.deps + deps
        ],
        output = compiled_jar,
        java_toolchain = toolchain.java_toolchain,
        host_javabase = toolchain.host_javabase,
    )
    return java_info

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
    repo = "@io_grpc_grpc_java"

    #    native.register_toolchains("@io_grpc_grpc_java//toolchain:all")
    native.register_toolchains(
        repo + "//toolchain:normal_android_toolchain",
        repo + "//toolchain:lite_android_toolchain",
        repo + "//toolchain:normal_default_toolchain",
        repo + "//toolchain:lite_default_toolchain",
    )
