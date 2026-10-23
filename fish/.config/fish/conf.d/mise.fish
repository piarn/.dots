# mise: switches go/node/python/... to whatever the current project's
# mise.toml or .tool-versions pins, on every cd. Non-interactive shells and
# apps launched from sway get the same tools through the shims directory
# (~/.config/environment.d/10-langs.conf).
if status is-interactive; and type -q mise
    mise activate fish | source
end
