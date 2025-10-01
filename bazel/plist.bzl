def _extract_xcode_all_settings_impl(ctx):
    """Extracts all settings (versions + INFOPLIST_KEY_*) from Xcode project file"""
    output = ctx.actions.declare_file(ctx.label.name + ".settings")
    
    ctx.actions.run_shell(
        inputs = [ctx.file.xcode_project],
        outputs = [output],
        command = "bash {script} {project} {output} {target}".format(
            script = ctx.file._script.path,
            project = ctx.file.xcode_project.path,
            output = output.path,
            target = ctx.attr.target_name,
        ),
        tools = [ctx.file._script],
    )
    
    return [DefaultInfo(files = depset([output]))]

extract_xcode_all_settings = rule(
    implementation = _extract_xcode_all_settings_impl,
    attrs = {
        "xcode_project": attr.label(allow_single_file = True, mandatory = True),
        "target_name": attr.string(default = "OpenCoder"),
        "_script": attr.label(
            default = "//bazel:extract_xcode_all_settings.sh",
            allow_single_file = True,
        ),
    },
)

# Keep old rule for backward compatibility
def _extract_xcode_version_impl(ctx):
    """Extracts version info from Xcode project file (legacy - use extract_xcode_all_settings)"""
    output = ctx.actions.declare_file(ctx.label.name + ".version")
    
    ctx.actions.run_shell(
        inputs = [ctx.file.xcode_project],
        outputs = [output],
        command = "bash {script} {project} {output}".format(
            script = ctx.file._script.path,
            project = ctx.file.xcode_project.path,
            output = output.path,
        ),
        tools = [ctx.file._script],
    )
    
    return [DefaultInfo(files = depset([output]))]

extract_xcode_version = rule(
    implementation = _extract_xcode_version_impl,
    attrs = {
        "xcode_project": attr.label(allow_single_file = True, mandatory = True),
        "_script": attr.label(
            default = "//bazel:extract_xcode_version.sh",
            allow_single_file = True,
        ),
    },
)

def _generate_plist_from_settings_impl(ctx):
    """Generates Info.plist from all Xcode settings (no template needed)"""
    output = ctx.actions.declare_file(ctx.attr.output_name)
    
    ctx.actions.run_shell(
        inputs = [ctx.file.settings_file],
        outputs = [output],
        command = "bash {script} {settings} {output} '{display_name}'".format(
            script = ctx.file._script.path,
            settings = ctx.file.settings_file.path,
            output = output.path,
            display_name = ctx.attr.display_name,
        ),
        tools = [ctx.file._script],
    )
    
    return [DefaultInfo(files = depset([output]))]

generate_plist_from_settings = rule(
    implementation = _generate_plist_from_settings_impl,
    attrs = {
        "settings_file": attr.label(allow_single_file = True, mandatory = True),
        "display_name": attr.string(mandatory = True),
        "output_name": attr.string(mandatory = True),
        "_script": attr.label(
            default = "//bazel:generate_plist_from_settings.sh",
            allow_single_file = True,
        ),
    },
)

# Keep old template-based rule for backward compatibility
def _generate_plist_impl(ctx):
    """Generates Info.plist from template with version substitution (legacy)"""
    output = ctx.actions.declare_file(ctx.attr.output_name)
    
    # Create substitution script
    script = """
    source {version_file}
    sed -e "s/{{{{MARKETING_VERSION}}}}/${{MARKETING_VERSION}}/g" \\
        -e "s/{{{{CURRENT_PROJECT_VERSION}}}}/${{CURRENT_PROJECT_VERSION}}/g" \\
        -e "s/{{{{DISPLAY_NAME}}}}/{display_name}/g" \\
        {template} > {output}
    """.format(
        version_file = ctx.file.version_info.path,
        template = ctx.file.template.path,
        output = output.path,
        display_name = ctx.attr.display_name,
    )
    
    ctx.actions.run_shell(
        inputs = [ctx.file.template, ctx.file.version_info],
        outputs = [output],
        command = script,
    )
    
    return [DefaultInfo(files = depset([output]))]

generate_plist = rule(
    implementation = _generate_plist_impl,
    attrs = {
        "template": attr.label(allow_single_file = [".template"], mandatory = True),
        "version_info": attr.label(allow_single_file = True, mandatory = True),
        "display_name": attr.string(mandatory = True),
        "output_name": attr.string(mandatory = True),
    },
)