# Contributing

Thanks for wanting to make Bandje better.

## Issues

Bug reports and ideas are welcome as [issues](https://github.com/neurendal/bandje/issues). For a bug, say which app (Mac, iPhone or iPad), which version, and what you did, saw and expected. Please don't attach recordings or transcripts of real conversations.

## Pull requests

1. **Sign the CLA.** Bandje is GPL-3.0, and Neurendal B.V. also ships it on the App Store under its own license. To include your change there too, we need the rights in the [Contributor License Agreement](CLA.md). You sign it by ticking the box in the pull request template. Without it we can't take the pull request.
2. **Keep it small and focused.** One fix or feature per pull request. For anything bigger than a fix, open an issue first so we can agree on it before you spend time on it.
3. **Keep the promises.** No networking code (`scripts/check-no-network.sh` must pass), no analytics, no new dependencies, no screen recording. Everything stays on the device.
4. **Test it.** `make test` for the Mac app, `make test` for iOS, and the network check. Say what you tested in the pull request.
5. **Match the style.** Swift, few files, no abstractions "for later". Code and comments in English.

## How a pull request gets into a release

This repository is a release mirror: the code is developed in a private repository and published here per App Store release, with one commit per release. So we don't merge pull requests here directly. When we accept yours, we apply it in the development repository with you as co-author, credit you in the changelog, and close the pull request once the release with your change is published here.

## Security

Found a security or privacy problem? Don't open a public issue. Mail bandje@neurendal.com instead.
