# Contributing

Open an issue to discuss a proposed change, then submit a focused pull request against main. Run `zsh scripts/test.sh` and `zsh scripts/build.sh`. Include the behavior change, validation and any limitations in the PR description. Do not include API keys, private account details, signing material, or personal diagnostic files.

Keep dependencies minimal, network requests bounded, provider adapters separate from UI, and version/update behavior covered by adversarial-input checks. Do not add certificate-validation exceptions or automatic code execution to the updater. See [the release guide](docs/RELEASING.md) and [security policy](SECURITY.md). Contributions and use remain subject to LICENSE.txt.
