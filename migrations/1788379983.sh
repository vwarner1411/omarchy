echo "Install Sidra for Apple Music with Tokyo Night styling"

omarchy-pkg-aur-add sidra-bin

omarchy-refresh-config Sidra/custom.css

sidra_config="$HOME/.config/Sidra/config.json"
sidra_config_tmp=$(mktemp "$HOME/.config/Sidra/config.json.XXXXXX")
trap 'rm -f "$sidra_config_tmp"' EXIT

if [[ -f $sidra_config ]]; then
  jq '.theme = "custom"' "$sidra_config" > "$sidra_config_tmp"
else
  jq -n '{theme: "custom"}' > "$sidra_config_tmp"
fi

mv "$sidra_config_tmp" "$sidra_config"
trap - EXIT
