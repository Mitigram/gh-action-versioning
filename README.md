# Somewhat Opinionated Semantic Versioning

This action attempts to generate good semantic versions for use in packages,
Docker tags, etc. out of the git information (branch, tag, number of commits).
It assumes that:

+ You use the `main` (or `master`) branch as the single source of truth.
+ You make releases out of the main branch, using tags that will contain a
  version number. These tags might be prefixed by a `v` and can contain a
  slightly relaxed semantic version, e.g. `v1.0.2` or `2.2` would work. The
  semantic version generated will be strict, as in `<major>.<minor>.<patch>`.

Pre-release semantic versions will be generated for any commit that does not
happen as a result of release tagging. These versions will contain the expected
semantic patch version of the next (coming) release, including some information
of the branch they are made on and how far from the latest tag this is.

## Usage

This action is designed to have good defaults and has a main output called
`semver` that can be used to tag artifacts generated below in your workflows.
This action will generate a number of additional outputs, see
[action.yml](./action.yml).

By default, for each existing output, this action will also create an
environment variable prefixed by `CI_` followed by the name of the output, but
in uppercase and with single dashes `-` replaced by underscores `_`. Out of
these outputs, the `semver` (and associated environment variable `CI_SEMVER`) is
the most important one.

### Examples

#### Releasing

When creating a release, perhaps using the GitHub UI for releases, and thus
creating a tag called `v1.2.4`, the `semver` action output will be set to
`1.2.4` (note that the leading `v` has automatically been removed from the
original tag).

Similarily, when releasing with a more laxist tag called `0.2`, the `semver`
action output will be set to `0.2.0`, i.e. a patch number of `0` will
automatically be appended to the version number.

#### Merging Features

When merging a feature branch, some time after a tag called `v1.2.4`, the
`semver` action output will be set to `1.2.5-main.34` (where `34` is the number
of commits/merges into master since the last tag).

#### Feature branches

When working on a feature branch called `feature/my-feature`, and if you wanted
to generate artifacts from that branch, the `semver` action output might be set
to `1.2.5-my-feature.46`. Note that only `my-feature`, i.e. everything after the
trailing slash in the branch name, appears as part of the pre-release identifier
in the version number.

### Inputs

The following inputs are available to tweak the behaviour of this action.

#### `prerelease`

When this is set to a non-empty value, the value of `prerelase` will be used, as
is, as the label to be used in the pre-release identifier of the semantic
version, if relevant. `prerelease` **must** follow the [BNF] for pre-release
identifiers.

By default, `prerelease` is empty. The label to use in the pre-release
identifier of the semantic version will come from the short branch name. The
short branch name is composed of all characters after the trailing slash in the
branch name. All characters that are not allowed according to the [BNF] will
simply be omitted.

  [BNF]: https://semver.org/spec/v2.0.0.html#backusnaur-form-grammar-for-valid-semver-versions

#### `namespace`

The `namespace` input will automatically be prefixed to the name of all the
environment variables that are set by this action. When generating variable
names, any trailing underscore `_` will be removed from the value of the
`namespace` input and a mandatory `_` will be inserted between the namespace and
the name of the variable generated out of the name of the action output. The
default value for the namespace is `CI`, meaning that there will be, for
example, an environment variable called `CI_SEMVER` in the github workflow
environment once the action has been run.

It is possible to turn off environment variable exporting by setting the value
of `namespace` to an empty string.

#### `options`

This is an internal input, used mostly for debugging. Any value given to
`options` will blindly be appended as part of the options to the shell script
that implements this action. You might want to set this to `-v` to increase
verbosity in debugging situations.
