load(":compiler.bzl", _GrpcProtoCompiler = "GrpcProtoCompiler")

_GrpcAspectInfo = provider(
    fields = {
        "exports": "List of JavaInfo targets to export from the consuming rule",
        "jars": "Depset<File> of compiled jars",
        "importmap": "(preorder)Depset[Tuple[Importpath,File]] of transitive protos",
        "imports": "(preorder)Depset[File] of transitive protos",
    },
)

_IMPORTS_DEPSET_ORDER = "preorder"

def _importmap_args(import_file_tuple):
    i, f = import_file_tuple
    return "-I%s=%s" % (i, f.path)

def _aspect_impl(target, ctx):
    # proto_info = target[ProtoInfo] # <- update provider when ProtoInfo is a real thing
    proto_info = target.proto
    compiler = ctx.attr._compiler[_GrpcProtoCompiler]

    # return (and merge) transitive deps if there are no sources to compile
    if len(proto_info.direct_sources) == 0:
        java_info = java_common.merge([dep[JavaInfo] for dep in ctx.rule.attr.deps])
        return struct(
            proto_java = java_info,
            providers = [java_info, _GrpcAspectInfo(
                exports = compiler.exports,
                jars = depset(transitive = [
                    dep[_GrpcAspectInfo].jars
                    for dep in ctx.rule.attr.deps
                ]),
                importmap = depset(transitive = [
                    dep[_GrpcAspectInfo].importmap
                    for dep in ctx.rule.attr.deps
                ]),
                imports = depset(transitive = [
                    dep[_GrpcAspectInfo].imports
                    for dep in ctx.rule.attr.deps
                ]),
            )],
        )

    java_srcs = ctx.actions.declare_file("%s/%s-java-sources.jar" % (compiler.path_fragment, ctx.rule.attr.name))
    grpc_srcs = ctx.actions.declare_file("%s/%s-grpc-sources.jar" % (compiler.path_fragment, ctx.rule.attr.name))
    compiled_jar = ctx.actions.declare_file("%s/%s.jar" % (compiler.path_fragment, ctx.rule.attr.name))

    # Tuples of [ImportedName => File]
    direct_importmap = []
    proto_files = []
    prefix = proto_info.proto_source_root + "/"
    for f in proto_info.direct_sources:
        imported_name = f.short_path
        if f.short_path.startswith(prefix):
            imported_name = imported_name[len(prefix):]
        direct_importmap += [(imported_name, f)]
        proto_files += [f]

    # create depsets for use in compilation action & to output via provider
    importmap = depset(direct = direct_importmap, transitive = [
        dep[_GrpcAspectInfo].importmap
        for dep in ctx.rule.attr.deps
    ], order = _IMPORTS_DEPSET_ORDER)
    imports = depset(direct = proto_files, transitive = [
        dep[_GrpcAspectInfo].imports
        for dep in ctx.rule.attr.deps
    ], order = _IMPORTS_DEPSET_ORDER)

    protoc = compiler.protoc.files_to_run.executable
    grpc_plugin = compiler.grpc_plugin.files_to_run.executable
    java_plugin = compiler.java_plugin.files_to_run.executable if compiler.java_plugin else None

    # generate java & grpc srcs
    args = ctx.actions.args()
    args.add_all(importmap, map_each = _importmap_args)
    args.add("--plugin=protoc-gen-grpc-java=%s" % grpc_plugin.path)
    args.add("--grpc-java_out={opts}:{file}".format(
        opts = ",".join(compiler.grpc_plugin_opts),
        file = grpc_srcs.path,
    ))
    if java_plugin:
        args.add("--plugin=protoc-gen-javaplugin=%s" % java_plugin.path)
        args.add("--javaplugin_out={opts}:{file}".format(
            opts = ",".join(compiler.java_plugin_opts),
            file = java_srcs.path,
        ))
    else:
        args.add("--java_out={opts}:{file}".format(
            opts = ",".join(compiler.java_plugin_opts),
            file = java_srcs.path,
        ))
    args.add_all(proto_files)

    # run the action
    # merge the srcjars
    # compile the merged jar
    ctx.actions.run(
        inputs = imports,
        outputs = [java_srcs, grpc_srcs],
        executable = protoc,
        arguments = [args],
        tools = [
            grpc_plugin,
        ] + ([java_plugin] if java_plugin else []),
    )
    sources_jar = java_common.pack_sources(
        ctx.actions,
        output_jar = compiled_jar,
        source_jars = [grpc_srcs, java_srcs],
        java_toolchain = compiler._java_toolchain,
        host_javabase = compiler._host_javabase,
    )
    compile_deps = [
        dep[JavaInfo]
        for dep in compiler.deps + ctx.rule.attr.deps
    ]
    java_common.compile(
        ctx,
        source_jars = [sources_jar],
        deps = compile_deps,
        output = compiled_jar,
        java_toolchain = compiler._java_toolchain,
        host_javabase = compiler._host_javabase,
    )

    # construct the providers:
    # - JavaInfo
    # - GrpcAspectInfo
    java_info = JavaInfo(
        output_jar = compiled_jar,
        compile_jar = compiled_jar,
        source_jar = sources_jar,
        deps = compile_deps,
    )
    return struct(
        # additionally return legacy provider so IntelliJ plugin is happy :-\
        proto_java = java_info,
        providers = [java_info, _GrpcAspectInfo(
            exports = compiler.exports,
            jars = depset(
                direct = [compiled_jar],
                transitive = [
                    dep[_GrpcAspectInfo].jars
                    for dep in ctx.rule.attr.deps
                ],
            ),
            imports = imports,
            importmap = importmap,
        )],
    )

def _grpc_aspect(compiler):
    return {
        "implementation": _aspect_impl,
        "attr_aspects": ["deps"],
        "fragments": ["java"],
        "provides": ["proto_java", JavaInfo],
        "attrs": {
            "_compiler": attr.label(
                providers = [_GrpcProtoCompiler],
                default = Label(compiler),
            ),
        },
    }

def _rule_impl(ctx):
    # exports come from the aspect's compiler, are the same for all deps
    # so we only need to grab one
    exports = ctx.attr.deps[0][_GrpcAspectInfo].exports

    # Combine generated & configured jars
    java_info = java_common.merge([
        dep[JavaInfo]
        for dep in ctx.attr.deps + exports + ctx.attr.transport
    ])
    compiled_jars = depset(transitive = [
        dep[_GrpcAspectInfo].jars
        for dep in ctx.attr.deps
    ])
    return [
        java_info,
        DefaultInfo(files = compiled_jars),
    ]

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
        provides = [JavaInfo],
    )

_normal_aspect = aspect(**_grpc_aspect("//java_grpc_library:grpc_java"))
java_grpc_library = _grpc_rule(_normal_aspect)

_lite_aspect = aspect(**_grpc_aspect("//java_grpc_library:grpc_javalite"))
java_lite_grpc_library = _grpc_rule(_lite_aspect)
