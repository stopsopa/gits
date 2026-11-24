#!/bin/bash

# used in git@github.secureserver.net:sdzialowski/PEX_dev.git

GITSTORAGETARGETDIR="git@github.com:stopsopa__gitstorage.git"


# paths will be solved from directory where gitstorage-config.sh is, usually it means from .git directory
GITSTORAGELIST=(

    "gitstorage-config.sh::$GITSTORAGETARGETDIR/gitstorage-config.sh"



    "HELP.md::$GITSTORAGETARGETDIR/HELP.md"
# this one needs to be mounted here:
#    ~/Workspace/PEX_dev sdzialowski √ pwd
#    /Users/sdzialowski/Workspace/PEX_dev
#    ~/Workspace/PEX_dev sdzialowski √ ls -la | grep HEL
#    lrwxr-xr-x    1 sdzialowski  staff     57 Oct 17  2022 _HELP.md -> ../SPECIAL_storage/SPECIAL_storage/.git/HELP.md



    "~/.zshrc::$GITSTORAGETARGETDIR/.zshrc"
    "~/.zshenv::$GITSTORAGETARGETDIR/.zshenv"
    "~/.zprofile::$GITSTORAGETARGETDIR/.zprofile"
    "~/.config/husky/init.sh::$GITSTORAGETARGETDIR/.config/husky/init.sh"

    "~/.bashrc::$GITSTORAGETARGETDIR/.bashrc"
    "~/.bash_profile::$GITSTORAGETARGETDIR/.bash_profile"
    "~/.any_shell_common.sh::$GITSTORAGETARGETDIR/.any_shell_common.sh"

    "links.sh::$GITSTORAGETARGETDIR/links.sh"
    "xx.cjs::${GITSTORAGETARGETDIR}/xx.cjs"

    # standalone vscode README.md for all envs
    "~/Workspace/vscode/README.md::$GITSTORAGETARGETDIR/vscode/README.md"
    "~/Workspace/vscode/.gitignore::$GITSTORAGETARGETDIR/vscode/.gitignore"

    # standalone vscode configs for lua
    "~/Workspace/vscode/lua/lua-logo.png::$GITSTORAGETARGETDIR/vscode/lua/lua-logo.png"
    "~/Workspace/vscode/lua/Lua-Logo.svg::$GITSTORAGETARGETDIR/vscode/lua/Lua-Logo.svg"
    "~/Workspace/vscode/lua/code-portable-data/user-data/User/keybindings.json::$GITSTORAGETARGETDIR/vscode/lua/code-portable-data/user-data/User/keybindings.json"
    "~/Workspace/vscode/lua/code-portable-data/user-data/User/settings.json::$GITSTORAGETARGETDIR/vscode/lua/code-portable-data/user-data/User/settings.json"

    # standalone vscode configs for javascript
    "~/Workspace/vscode/javascript/Unofficial_JavaScript_logo_2.svg::$GITSTORAGETARGETDIR/vscode/javascript/Unofficial_JavaScript_logo_2.svg"
    "~/Workspace/vscode/javascript/code-portable-data/user-data/User/keybindings.json::$GITSTORAGETARGETDIR/vscode/javascript/code-portable-data/user-data/User/keybindings.json"
    "~/Workspace/vscode/javascript/code-portable-data/user-data/User/settings.json::$GITSTORAGETARGETDIR/vscode/javascript/code-portable-data/user-data/User/settings.json"
    "~/Workspace/vscode/javascript/code-portable-data/user-data/User/snippets/typescriptreact.json::$GITSTORAGETARGETDIR/vscode/javascript/code-portable-data/user-data/User/snippets/typescriptreact.json"    
    "~/Workspace/vscode/javascript/code-portable-data/user-data/User/snippets/javascriptreact.json::$GITSTORAGETARGETDIR/vscode/javascript/code-portable-data/user-data/User/snippets/javascriptreact.json"    

    # standalone vscode configs for java
    "~/Workspace/vscode/java/java.png::$GITSTORAGETARGETDIR/vscode/java/java.png"
    "~/Workspace/vscode/java/code-portable-data/user-data/User/keybindings.json::$GITSTORAGETARGETDIR/vscode/java/code-portable-data/user-data/User/keybindings.json"
    "~/Workspace/vscode/java/code-portable-data/user-data/User/settings.json::$GITSTORAGETARGETDIR/vscode/java/code-portable-data/user-data/User/settings.json"

    # standalone vscode configs for python
    "~/Workspace/vscode/python/python-logo-only.svg::$GITSTORAGETARGETDIR/vscode/python/python-logo-only.svg"
    "~/Workspace/vscode/python/code-portable-data/user-data/User/keybindings.json::$GITSTORAGETARGETDIR/vscode/python/code-portable-data/user-data/User/keybindings.json"
    "~/Workspace/vscode/python/code-portable-data/user-data/User/settings.json::$GITSTORAGETARGETDIR/vscode/python/code-portable-data/user-data/User/settings.json"

    # standalone vscode configs for go
    "~/Workspace/vscode/go/Go-Logo_LightBlue.svg::$GITSTORAGETARGETDIR/vscode/go/Go-Logo_LightBlue.svg"
    "~/Workspace/vscode/go/code-portable-data/user-data/User/keybindings.json::$GITSTORAGETARGETDIR/vscode/go/code-portable-data/user-data/User/keybindings.json"
    "~/Workspace/vscode/go/code-portable-data/user-data/User/settings.json::$GITSTORAGETARGETDIR/vscode/go/code-portable-data/user-data/User/settings.json"

    "~/Library/Application Support/Antigravity IDE/User/keybindings.json::$GITSTORAGETARGETDIR/antigravity/User/keybindings.json"
    "~/Library/Application Support/Antigravity IDE/User/settings.json::$GITSTORAGETARGETDIR/antigravity/User/settings.json"
    
    "~/Library/Application Support/Devin/User/keybindings.json::$GITSTORAGETARGETDIR/devin/User/keybindings.json"
    "~/Library/Application Support/Devin/User/settings.json::$GITSTORAGETARGETDIR/devin/User/settings.json"
    

    "~/Library/Application Support/Cursor/User/settings.json::$GITSTORAGETARGETDIR/vscode/cursor/settings.json"
    "~/Library/Application Support/Cursor/User/keybindings.json::$GITSTORAGETARGETDIR/vscode/cursor/keybindings.json"    

    "~/Library/Application Support/Code/User/keybindings.json::$GITSTORAGETARGETDIR/vscode/keybindings.json"
    "~/Library/Application Support/Code/User/settings.json::$GITSTORAGETARGETDIR/vscode/settings.json"

    "~/.config/mpv/mpv.conf::$GITSTORAGETARGETDIR/MPV-player/mpv/mpv.conf"
    "~/.config/mpv/input.conf::$GITSTORAGETARGETDIR/MPV-player/mpv/input.conf"
    "~/.config/mpv/script-opts/osc.conf::$GITSTORAGETARGETDIR/MPV-player/mpv/script-opts/osc.conf"
    "~/.config/mpv/scripts/osc-visibility-toggle.lua::$GITSTORAGETARGETDIR/MPV-player/mpv/scripts/osc-visibility-toggle.lua"

    # gdm1_root
    "../../gdm1_root/Users/sdzialowski/.gitignore_global::$GITSTORAGETARGETDIR/gdm1_root/.gitignore_global"
    "../../gdm1_root/Users/sdzialowski/.gitconfig::$GITSTORAGETARGETDIR/gdm1_root/.gitconfig"
    "../../gdm1_root/Users/sdzialowski/xx.cjs::$GITSTORAGETARGETDIR/gdm1_root/xx.cjs"

    "~/.asdfrc::$GITSTORAGETARGETDIR/.asdfrc"   
    "~/.tool-versions::$GITSTORAGETARGETDIR/.tool-versions"   

    "../../gdm1_root/Users/sdzialowski/.m2/settings_gd.xml::$GITSTORAGETARGETDIR/gdm1_root/.m2/settings_gd.xml"
    "../../gdm1_root/Users/sdzialowski/.m2/settings_stopsopa.xml::$GITSTORAGETARGETDIR/gdm1_root/.m2/settings_stopsopa.xml"
    "../../gdm1_root/Users/sdzialowski/.m2/settings_max.xml::$GITSTORAGETARGETDIR/gdm1_root/.m2/settings_stopsopa.xml"
    "../../gdm1_root/Users/sdzialowski/.m2/settings_toan.xml::$GITSTORAGETARGETDIR/gdm1_root/.m2/settings_stopsopa.xml"

    "../../gdm1_root/Users/sdzialowski/.aws/config::$GITSTORAGETARGETDIR/gdm1_root/.aws/config"
    "../../gdm1_root/Users/sdzialowski/.aws/credentials::$GITSTORAGETARGETDIR/gdm1_root/.aws/credentials"

    "../../gdm1_root/etc/hosts::$GITSTORAGETARGETDIR/gdm1_root/etc/hosts"
    "../../gdm1_root/Users/sdzialowski/tools/aliasScripts/vault.sh::$GITSTORAGETARGETDIR/gdm1_root/vault.sh"
    "../../gdm1_root/Users/sdzialowski/.npmrc::$GITSTORAGETARGETDIR/gdm1_root/.npmrc"
    "../../gdm1_root/Users/sdzialowski/gitsstate.sh::$GITSTORAGETARGETDIR/gdm1_root/gitsstate.sh"

    # "../../gdm1_root/Users/sdzialowski/Library/LaunchAgents/com.os-browser-bridge.node.plist::$GITSTORAGETARGETDIR/gdm1_root/Library/LaunchAgents/com.os-browser-bridge.node.plist"
    # "../../szm114_root/Users/szdz/Library/LaunchAgents/com.os-browser-bridge.node.plist::$GITSTORAGETARGETDIR/szm114_root/Library/LaunchAgents/com.os-browser-bridge.node.plist"
    "../../gdm1_root/Users/sdzialowski/.config/karabiner/karabiner.json::$GITSTORAGETARGETDIR/gdm1_root/karabiner/karabiner.json"
    "../../szm114_root/Users/szdz/.config/karabiner/karabiner.json::$GITSTORAGETARGETDIR/szm114_root/karabiner/karabiner.json"

    # gdm1
    "../../gdm1/PEX_dev/GDCORP-BRANDS-RESELLER__ux-pipeline/GDCORP-BRANDS-RESELLER__ux-pipeline/vars/multistageUIPipeline.groovy::$GITSTORAGETARGETDIR/gdm1/GDCORP-BRANDS-RESELLER__ux-pipeline/multistageUIPipeline.groovy"

    "../../gdm1/PEX_dev/GDCORP-BRANDS-RESELLER__pipeline/GDCORP-BRANDS-RESELLER__pipeline/vars/bfPipeline.groovy::$GITSTORAGETARGETDIR/gdm1/GDCORP-BRANDS-RESELLER__pipeline/vars/bfPipeline.groovy"
    "../../gdm1/PEX_dev/GDCORP-BRANDS-RESELLER__pipeline/GDCORP-BRANDS-RESELLER__pipeline/src/com/godaddy/emea/bf/pipeline/PipelineConfig.groovy::$GITSTORAGETARGETDIR/gdm1/PEX_dev/GDCORP-BRANDS-RESELLER__pipeline/GDCORP-BRANDS-RESELLER__pipeline/src/com/godaddy/emea/bf/pipeline/PipelineConfig.groovy"

    "../../gdm1/PEX_dev/pull.sh::$GITSTORAGETARGETDIR/gdm1/pull.sh"
    "../../gdm1/PEX_dev/jwt.sh::$GITSTORAGETARGETDIR/gdm1/PEX_dev/jwt.sh"
    "../../gdm1/PEX_dev/__/ecomm-shared.client.cp.api.dev-godaddy.com.key::$GITSTORAGETARGETDIR/gdm1/PEX_dev/__/ecomm-shared.client.cp.api.dev-godaddy.com.key"
    "../../gdm1/PEX_dev/__/ecomm-shared.client.cp.api.dev-godaddy.com.crt::$GITSTORAGETARGETDIR/gdm1/PEX_dev/__/ecomm-shared.client.cp.api.dev-godaddy.com.crt"

    # interesting github actions setups vvvvvvvvvvvvvv
    
    "../../gdm1_root/Users/sdzialowski/Workspace/PEX_dev/GDCORP-BRANDS-RESELLER__infrastructure/GDCORP-BRANDS-RESELLER__infrastructure/.github/workflows/apply-infrastructure.yaml::$GITSTORAGETARGETDIR/gdm1_root/GithubActionsWorkflows/GDCORP-BRANDS-RESELLER__infrastructure/apply-infrastructure.yaml"
    "../../gdm1_root/Users/sdzialowski/Workspace/PEX_dev/GDCORP-BRANDS-RESELLER__infrastructure/GDCORP-BRANDS-RESELLER__infrastructure/.github/workflows/cirrus-scan.yaml::$GITSTORAGETARGETDIR/gdm1_root/GithubActionsWorkflows/GDCORP-BRANDS-RESELLER__infrastructure/cirrus-scan.yaml"
    "../../gdm1_root/Users/sdzialowski/Workspace/PEX_dev/GDCORP-BRANDS-RESELLER__infrastructure/GDCORP-BRANDS-RESELLER__infrastructure/.github/workflows/deploy.yaml::$GITSTORAGETARGETDIR/gdm1_root/GithubActionsWorkflows/GDCORP-BRANDS-RESELLER__infrastructure/deploy.yaml"
    # interesting github actions setups ^^^^^^^^^^^^

    # szm114_root
    "../../szm114_root/Users/szdz/.gitignore_global::$GITSTORAGETARGETDIR/szm114_root/.gitignore_global"
    "../../szm114_root/Users/szdz/.gitconfig::$GITSTORAGETARGETDIR/szm114_root/.gitconfig"
    "../../szm114_root/Users/szdz/.m2/settings.xml::$GITSTORAGETARGETDIR/szm114_root/.m2/settings.xml"
    "../../szm114_root/Users/szdz/xx.cjs::$GITSTORAGETARGETDIR/szm114_root/xx.cjs"
    "../../szm114_root/etc/hosts::$GITSTORAGETARGETDIR/szm114_root/etc/hosts"

    "../../gdm1/pull.sh::$GITSTORAGETARGETDIR/gdm1/Workspace/pull.sh"
    "../../szm114/pull.sh::$GITSTORAGETARGETDIR/szm114/Workspace/pull.sh"

    "excalidraw/excalidraw.excalidraw::$GITSTORAGETARGETDIR/excalidraw/excalidraw.excalidraw"

    "../../szm114_root/Users/szdz/.pi/agent/trust.json::$GITSTORAGETARGETDIR/szm114_root/.pi/agent/trust.json"
    "../../szm114_root/Users/szdz/.pi/agent/models.json::$GITSTORAGETARGETDIR/szm114_root/.pi/agent/models.json"
    "../../szm114_root/Users/szdz/.pi/agent/settings.json::$GITSTORAGETARGETDIR/szm114_root/.pi/agent/settings.json"
    "../../szm114_root/Users/szdz/.pi/agent/keybindings.json::$GITSTORAGETARGETDIR/szm114_root/.pi/agent/keybindings.json"
    "../../szm114_root/Users/szdz/.pi/agent/auth.json::$GITSTORAGETARGETDIR/szm114_root/.pi/agent/auth.json"
    "../../szm114_root/Users/szdz/.claude/settings.json::$GITSTORAGETARGETDIR/szm114_root/.claude/settings.json"


    "../../szm114_root/Users/szdz/.agents/.skill-lock.json::$GITSTORAGETARGETDIR/szm114_root/.agents/.skill-lock.json"
)


set -o pipefail
INTELIJ="$(ls -la ../gdm1_root/Users/sdzialowski/Library/Application\ Support/JetBrains/ | awk '{ print $9 }' | grep  -i -E "^IntelliJIdea" | sort -r | head -n 1)"

if [ "${?}" = "0" ]; then
  echo "all good ${INTELIJ}"
  TRAPS+=("../../gdm1_root/Users/sdzialowski/Library/Application Support/JetBrains/${INTELIJ}/scratches/scratch.http::$GITSTORAGETARGETDIR/gdm1_root/Library/Application Support/JetBrains/IntelliJIdeaxxxx.x/scratches/scratch.http")
  TRAPS+=("../../gdm1_root/Users/sdzialowski/Library/Application Support/JetBrains/${INTELIJ}/scratches/businessfabric__notifications.http::$GITSTORAGETARGETDIR/gdm1_root/Library/Application Support/JetBrains/IntelliJIdeaxxxx.x/scratches/businessfabric__notifications.http")
else
  cat <<EEE

  WARNING:
  WARNING:
  WARNING:

    couldn't extract INTELIJ current dir with command:
      ls -la ../../gdm1_root/Users/sdzialowski/Library/Application\ Support/JetBrains/ | awk '{ print $9 }' | grep  -i -E "^IntelliJIdea" | sort -r | head -n 1

    usually it means you have to install intelij first
    some files were skipped due to this, but don't worry, if files were uploaded then they are still there

  WARNING:
  WARNING:
  WARNING:

EEE

fi
set +o pipefail
