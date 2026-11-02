# Contributing

**English** · [Español](CONTRIBUTING.es.md)

These labs are open source (Apache License 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE)).
Anyone can contribute: fixes, new labs, better guides, translations, support for other platforms,
or improvements to the [configuration wizard](https://europesip.github.io/hcl-dx-compose-labs/about.html).

## How to contribute

1. Open an [issue](https://github.com/europesip/hcl-dx-compose-labs/issues) describing the problem or
   the improvement (for small fixes you can go straight to step 2).
2. Fork the repository, create a branch and make your changes.
3. Test them (see below) and open a pull request explaining what changes and how you tested it.

## Guidelines

- **Scripts**: comments and messages in English; idempotent (they can be run twice); every value
  comes from `env.sh` / `env.example.sh`, never hard-coded names, hosts or StorageClasses.
- **Guides**: always in both languages, `GUIDE.md` (English) and `GUIDE.es.md` (Spanish), and the same
  for `README` and `docs/`.
- **Test from scratch** before proposing a change to a lab: `common/99-cleanup.sh` and the labs again,
  on a cluster or on the Lab 0 PoC.
- **Never commit** `env.sh`, credentials, certificates, the HCL charts (`charts/`) or HCL images. They
  are in `.gitignore`; check `git status` before every commit.
- **Scope**: the labs are a PoC for learning. Production tuning is out of scope (see the notice in
  the README).
- **Attribution**: keep the [NOTICE](NOTICE) file and the mentions of EUROPESIP as the original
  author. You can add yourself as a contributor.

## Maintaining the configuration wizard

The wizard lives in [`docs/index.html`](docs/index.html) (the wizard) and
[`docs/about.html`](docs/about.html) (its presentation page), published on GitHub Pages. Its source
code is also in its own repository,
[europesip/hcl-dx-compose-labs-wizard](https://github.com/europesip/hcl-dx-compose-labs-wizard):
**both copies must stay identical.**

Option C of the wizard (the self-contained `dx-install/` bundle) carries **a copy of 29 lab files**
(values, properties, LDIF, MCP server...) in the `LAB TEMPLATES` block of `docs/index.html`, because it
renders them with the user's values in the browser. When you change any of those lab files:

```bash
tools/sync-wizard-templates.py            # copies the lab files into docs/index.html
tools/sync-wizard-templates.py --check    # only reports whether the copy is out of date
```

Then copy `docs/index.html` and `docs/about.html` to the wizard repository and push both repositories.
The list of embedded files is at the top of [`tools/sync-wizard-templates.py`](tools/sync-wizard-templates.py).
`setup-postgres-dx.sql` is deliberately not embedded: it is not published.

To test the wizard: open `docs/index.html` in a browser, generate the three options and, for option
C, run the generated `install.sh` on an empty cluster.
