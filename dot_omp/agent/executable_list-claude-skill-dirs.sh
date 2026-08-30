#!/bin/sh
# Print each directory that holds Claude Code skills, one directory for each
# line. The omp config template turns this list into skills.customDirectories.
#
# omp does not expand globs in skills.customDirectories, so the setting must
# name every directory. This script finds them.
#
# The script prints two kinds of directory:
#   - ~/.claude/skills, which holds the skills that you write
#   - the skills of each installed marketplace plugin
#
# A plugin is installed when installed_plugins.json holds its
# "<plugin>@<marketplace>" key. The script skips a plugin that is only in the
# cache. The cache keeps one directory for each version, so the script takes
# the directory that changed last.

set -u

claude_dir="${HOME}/.claude"
installed="${claude_dir}/plugins/installed_plugins.json"

if [ -d "${claude_dir}/skills" ]; then
    echo "${claude_dir}/skills"
fi

[ -f "${installed}" ] || exit 0

for plugin_dir in "${claude_dir}"/plugins/cache/*/*/; do
    [ -d "${plugin_dir}" ] || continue
    plugin=$(basename "${plugin_dir}")
    marketplace=$(basename "$(dirname "${plugin_dir}")")
    grep -q "\"${plugin}@${marketplace}\"" "${installed}" || continue
    version=$(ls -1t "${plugin_dir}" 2>/dev/null | head -1)
    [ -n "${version}" ] || continue
    if [ -d "${plugin_dir}${version}/skills" ]; then
        echo "${plugin_dir}${version}/skills"
    fi
done

exit 0
