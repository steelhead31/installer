# Plan: Create linux_v3 — Simplified & Deduplicated Installer Pipeline

## Top-Level Overview

Create a new `linux_v3/` directory that is a complete copy of `linux_new/`, then apply all simplification and deduplication changes to the copy only. The existing `linux_new/` directory is **never touched**. All work is isolated to `linux_v3/`.

The changes fall into two categories:

1. **Jenkinsfile simplification** — collapse structural duplication in the pipeline stages (GPG signing, archiving, publishing, version-parsing) into reusable helpers.
2. **Template consolidation** — replace 70+ near-identical per-version Jinja2 templates (RHEL, SUSE, Debian, Alpine) with a single shared template per distro+type that uses `{% if %}` guards for version-specific differences. JDK/JRE 8 templates are structurally different and remain per-version.
3. **New `BUILD_DRY_RUN` parameter** — a new boolean that runs the full pipeline (spec generation, Docker builds, artifact archiving) but skips only the final `CheckAndUpload` calls to Artifactory. The existing `DRY_RUN` parameter (which skips everything after `Print Parameters`) is unchanged.

**Key constraints:**
- `linux_new/` is never modified.
- All existing `parameters { }` (names, types, defaults, descriptions) are preserved unchanged in `linux_v3/Jenkinsfile`.
- Existing `DRY_RUN` behaviour is unchanged.
- `generate_spec.py` 12-argument interface is unchanged.
- Rendered template output must be byte-for-byte identical to what the current per-version templates produce.
- All `linux_new` path references inside the copied Jenkinsfile are updated to `linux_v3`.

---

## Sub-Task 1 — Copy linux_new to linux_v3 and fix path references

**Status:** `[ ] pending`

### Intent
Create `linux_v3/` as an exact copy of `linux_new/`. Then update all hard-coded `linux_new` path strings inside `linux_v3/Jenkinsfile` so the pipeline finds templates and scripts in the right place. No logic changes yet — this sub-task is purely structural.

### Expected Outcomes
- `linux_v3/` exists with all files identical to `linux_new/` except for 8 path-string replacements in `linux_v3/Jenkinsfile`.
- `linux_new/` is untouched.
- The copied Jenkinsfile is syntactically valid and would run correctly against the `linux_v3/` directory tree.

### Todo List
1. `cp -r linux_new linux_v3`
2. In `linux_v3/Jenkinsfile`, replace every occurrence of the string `linux_new` with `linux_v3` (8 occurrences on lines 589, 596, 634, 641, 687, 696, 707, 713).
3. Update the header comment on line 1 to reference `create_installer_linux_v3` and remove the CI URL (it doesn't exist yet).

### Relevant Context
- The 8 `linux_new` occurrences in the Jenkinsfile: template paths (lines 589, 634, 687), `generate_spec.py` invocations (lines 596, 641, 696), `find` command (line 707), `dir()` block (line 713).
- No other files in the tree contain hard-coded `linux_new` paths (settings.gradle, build.gradle are relative and need no changes).

---

## Sub-Task 2 — Add BUILD_DRY_RUN parameter and wire it into Publish Packages

**Status:** `[ ] pending`

### Intent
Add a new `BUILD_DRY_RUN` boolean parameter to `linux_v3/Jenkinsfile`. When true, all stages run normally (Process Parameters, Validate Artifacts, Generate Spec File, Build & Archive Package) except the `Publish Packages` stage is skipped. This lets a user do a complete package build and inspect the built artifacts without uploading anything to Artifactory.

The existing `DRY_RUN` parameter (which skips all stages after `Print Parameters` — i.e. no build at all) is preserved unchanged.

### Expected Outcomes
- `parameters { }` block has a new `booleanParam(name: 'BUILD_DRY_RUN', defaultValue: true, description: 'Run all build stages but skip the final Artifactory publish — set to false for a full production run')` entry.
- The `Publish Packages` stage `when` expression changes from `!shouldSkipPipeline && !params.DRY_RUN` to `!shouldSkipPipeline && !params.DRY_RUN && !params.BUILD_DRY_RUN`.
- The `post { success { ... } }` block that triggers `publish_linux_pkg_src` also skips when `BUILD_DRY_RUN` is true (the source archive job has nothing new to publish if we haven't uploaded packages).
- All other stages are unaffected.

### Todo List
1. In the `parameters { }` block, add the new `BUILD_DRY_RUN` boolean param directly below the existing `DRY_RUN` param.
2. Update the `Publish Packages` stage `when` expression.
3. In the `post { success { } }` block, wrap the `build job: 'publish_linux_pkg_src'` call with `if (!params.BUILD_DRY_RUN)`.
4. Add a log line in `Print Parameters` to echo the value of `BUILD_DRY_RUN`.

### Relevant Context
- `linux_v3/Jenkinsfile` (after Sub-Task 1 path fix):
  - Existing `DRY_RUN` `when` guard: line 858 `expression { return !shouldSkipPipeline && !params.DRY_RUN }`
  - `post { success { ... } }`: lines 991–1010

---

## Sub-Task 3 — Collapse duplicated GPG signing and archive blocks (Build & Archive Package stage)

**Status:** `[ ] pending`

### Intent
In the `Build & Archive Package` stage, the GPG-signing logic and the `archiveArtifacts` logic each repeat the same structural pattern for every distro (alpine, debian, rhel, suse). Replace both with a data-driven approach using a per-distro config map so the structure is declared once.

### Expected Outcomes
- A `distroSigningConfig` map is declared once, mapping each distro name to its credential ID (or `null` for Debian which has no signing).
- A `distroArchiveConfig` map maps each distro name to its `[skipParam, depSubdir]`.
- The four separate GPG if/else blocks collapse to a single block doing a map lookup.
- The four separate archive if/else blocks collapse to a single parameterised block.
- Runtime behaviour is identical: same credentials, same archive globs, same skip echo messages.

### Todo List
1. At the start of the `Build & Archive Package` `script` block, define:
   ```groovy
   def distroSigningConfig = [
       alpine: 'adoptium-artifactory-rsa-key',
       debian: null,
       rhel:   'adoptium-artifactory-gpg-key',
       suse:   'adoptium-artifactory-gpg-key'
   ]
   def distroArchiveConfig = [
       alpine: [skip: params.SKIP_ALPINE, depDir: 'apk'],
       debian: [skip: params.SKIP_DEBIAN, depDir: 'deb'],
       rhel:   [skip: params.SKIP_RHEL,   depDir: 'rpm'],
       suse:   [skip: params.SKIP_SUSE,   depDir: 'rpm']
   ]
   ```
2. Replace the three nested `if (ENABLEGPGSIGNING)` blocks (lines 769–800) with:
   - Look up `credId = distroSigningConfig[DistArrayElement]`
   - If `credId != null`: use `withCredentials` with that credential
   - If `credId == null` (Debian): run `buildCli` directly with no credentials
   - Apply `--stacktrace` and `sh("$buildCli")` in the same single location
3. Replace the four `if (DistArrayElement == 'X' && !params.SKIP_X)` archive blocks (lines 809–844) with a single block using `distroArchiveConfig[DistArrayElement]`.
4. The `buildCli` construction (ARCH selection for rhel/suse vs debian vs alpine) at lines 761–767 is already compact and stays as-is.

### Relevant Context
- `linux_v3/Jenkinsfile` lines 769–843 (after Sub-Tasks 1–2).
- `PKGBUILDLABELRHEL` is shared for both `rhel` and `suse` — this is already handled in the node-label lookup and does not change.

---

## Sub-Task 4 — Collapse duplicated RHEL/SUSE publish blocks (Publish Packages stage)

**Status:** `[ ] pending`

### Intent
The RHEL upload block (~lines 919–945) and SUSE upload block (~lines 947–975) are structurally identical. The only differences are the glob prefix (`rhel` vs `suse`), the distro list variable, and the skip flag. Extract a single `uploadRpm` closure that is called twice.

### Expected Outcomes
- A `def uploadRpm` closure replaces the two ~28-line duplicated blocks.
- Closure is called as `uploadRpm('rhel', rhel_distros, params.SKIP_RHEL, 'RHEL')` and `uploadRpm('suse', suse_distros, params.SKIP_SUSE, 'SUSE')`.
- `CheckAndUpload` call signature is identical.

### Todo List
1. Define `def uploadRpm` as a closure at the top of the `Publish Packages` stage `script` block, parameterised as `{ String globPrefix, List distroList, boolean skip, String label -> ... }`.
2. Move the shared body (findFiles both globs, loop, extract arch, override src arch, inner distro loop, CheckAndUpload or skip echo) into the closure.
3. Replace both RHEL and SUSE blocks with the two closure calls.

### Relevant Context
- `linux_v3/Jenkinsfile` lines 919–975.
- `CheckAndUpload` function signature (line 165) must not change.

---

## Sub-Task 5 — Extract version-parsing and packagever helpers (Generate Spec File stage)

**Status:** `[ ] pending`

### Intent
The `Generate Spec File` stage contains three near-identical version-parsing + `packagever` construction blocks, one each for alpine, debian, and rhel/suse. The shared regex parse runs once at the top of the `DISTS_TO_BUILD.each` loop but the JDK8 version reformatting is re-derived inside each distro block. Extract two named helper functions defined above the `pipeline { }` block.

### Expected Outcomes
- `def parseVersionComponents(String pvers, boolean isJDK8)` returns `[release, version, build]` — the two regex patterns previously inline at lines 526–546 move here.
- `def buildPackageVer(release, version, build, String distType, String temurinIncrement)` returns `[packagever, changelogversion]` (changelogversion is `""` for alpine and debian). The JDK8 Alpine re-parse is handled inside this function for `distType == 'alpine'`.
- The three inline blocks in `Generate Spec File` each become two-line calls to these helpers.
- All output values (`packagever`, `changelogversion`, `upstreamversion`) are identical.

### Todo List
1. Define `parseVersionComponents` above the `pipeline` block (in the script preamble section alongside `downloadArtifact`, `validateChecksum`, etc.).
2. Define `buildPackageVer` above the `pipeline` block.
3. In `Generate Spec File`, replace the shared parse block (lines 525–547) with a call to `parseVersionComponents`.
4. Replace the alpine `packagever` derivation block (lines 560–581) with a call to `buildPackageVer('alpine', ...)`.
5. Replace the debian `packagever` derivation block (lines 608–625) with a call to `buildPackageVer('debian', ...)`.
6. Replace the rhel/suse `packagever` derivation block (lines 651–678) with a call to `buildPackageVer('rhel', ...)`.

### Relevant Context
- `linux_v3/Jenkinsfile` lines 525–699.
- `TemurinVersion` and `PackageReleaseVersion` are outer-scope variables — pass them as explicit parameters to `buildPackageVer`.
- `upstreamversion` and ARM32 handling for RHEL/SUSE (lines 658–683) stay inline after the helper call as they depend on `params.TAG` and the outer `PARCH`.

---

## Sub-Task 6 — Consolidate RHEL and SUSE spec templates (versions 11–26)

**Status:** `[ ] pending`

### Intent
The 7 JDK RHEL spec templates (`linux_v3/jdk/rhel/src/main/packaging/temurin/{11,17,21,23,24,25,26}/temurin-N-jdk.template.j2`) are 241 lines each and structurally identical except for version-specific tool inclusions and removals. Replace them with a single `temurin-jdk.template.j2` one level up (at `linux_v3/jdk/rhel/src/main/packaging/temurin/temurin-jdk.template.j2`) using Jinja2 `{% if %}` guards.

Apply the same consolidation to:
- `jre/rhel/` (7 JRE RHEL templates)
- `jdk/suse/` (7 JDK SUSE templates, which mirror RHEL)
- `jre/suse/` (7 JRE SUSE templates)

JDK/JRE version 8 templates (`8/temurin-8-jdk.template.j2` etc.) are structurally different and are left untouched.

### Expected Outcomes
- 4 consolidated spec templates replace 28 per-version files.
- Per-version directories 11–26 under those four paths are deleted from `linux_v3/`.
- `8/` directories in each path are preserved.
- Jenkinsfile `templatebase` for rhel/suse (line 687 after previous sub-tasks) uses a conditional path:
  - If `Release == 8`: keep existing per-version path
  - Otherwise: `./linux_v3/${PTYPE}/${DistArrayElement}/src/main/packaging/${PRODUCT}/${PRODUCT}-${PTYPE}.template.j2`
- Rendered `.spec` output is byte-for-byte identical to current per-version templates for all tested versions (11, 17, 21, 24).

### Version-conditional differences to encode (JDK RHEL, derived by diffing all versions):
- **All versions 11–26:** version number in `Name:`, `Provides:`, binary URL, java home path — all derived from `{{ upstream_version }}` / `{{ package_version }}` (already templated).
- **≥ 17:** Remove `jaotc`, `pack200`, `rmid`, `unpack200` from `%post` alternatives and `%preun` cleanup.
- **≥ 21:** Add `jwebserver` to `%post` alternatives and `%preun` cleanup.
- JRE templates have analogous but smaller tool lists — same conditional logic applies.

### Todo List
1. Read and diff all 7 JDK RHEL templates to produce the definitive version-conditional line list (verify against the sub-agent findings).
2. Author `linux_v3/jdk/rhel/src/main/packaging/temurin/temurin-jdk.template.j2` using `{% set release_num = upstream_version.split('.')[0] | int %}` at the top to drive `{% if release_num >= 17 %}` guards. (For non-JDK8, `upstream_version` starts with the major release number, e.g. `17.0.14+7`.)
3. Test render with `python3 linux_v3/generate_spec.py` for versions 11, 17, 21, 24 and diff against existing per-version output.
4. Repeat steps 1–3 for `jre/rhel/`, `jdk/suse/`, `jre/suse/`.
5. Delete per-version directories 11–26 from all four template paths.
6. Update `templatebase` in `linux_v3/Jenkinsfile` (rhel/suse block) with the conditional path logic.

### Relevant Context
- Current Jenkinsfile line (post Sub-Task 1): `templatebase = "./linux_v3/${PTYPE}/${DistArrayElement}/src/main/packaging/${PRODUCT}/${Release}/${PRODUCT}-${Release}-${PTYPE}.template.j2"`
- JDK8 special-case path: `./linux_v3/${PTYPE}/${DistArrayElement}/src/main/packaging/${PRODUCT}/8/${PRODUCT}-8-${PTYPE}.template.j2` — unchanged.

---

## Sub-Task 7 — Consolidate Debian templates (versions 11–26)

**Status:** `[ ] pending`

### Intent
The Debian packaging requires 3 files per version: `control`, `changelog`, `rules`. These are currently stored at `linux_v3/jdk/debian/src/main/packaging/temurin/{11,17,21,23,24,25,26}/debian/{control,changelog,rules}.template.j2` — 21 JDK files + 21 JRE files = 42 files for versions 11–26.

- `changelog.template.j2` is **100% identical** across all versions (pure Jinja2 variables) — one shared copy replaces 14 copies.
- `rules.template.j2` differs only in package name, priority number, and tool list — 1 shared template with `{% if %}` guards.
- `control.template.j2` differs in package name and the `Provides:` list (which grows by ~4 virtual package entries per major release) — 1 shared template with `{% if release_num >= N %}` guards.

JDK/JRE version 8 are left untouched.

### Expected Outcomes
- 3 consolidated Debian templates (at `linux_v3/jdk/debian/src/main/packaging/temurin/debian/{control,changelog,rules}.template.j2`) replace 21 JDK per-version files.
- Same 3 consolidated templates for `jre/debian/` replace 21 JRE per-version files.
- Per-version directories 11–26 under `jdk/debian/` and `jre/debian/` are deleted; `8/` stays.
- Jenkinsfile `templatebase` for debian uses conditional path (non-8 uses new shared path, 8 keeps existing path).
- Rendered output is byte-for-byte identical for all tested versions.

### Version-conditional differences to encode:
- `control.template.j2`: `Package:` name (`temurin-{{ release_num }}-jdk`), `Provides:` list grows — each release adds virtual packages for itself and all prior releases. Use `{% if release_num >= N %}` guards for each block of added virtual packages.
- `rules.template.j2`: package name, priority (`{{ release_num * 100 + 11 }}` for JDK, `{{ release_num * 100 + 12 }}` for JRE — can be computed inside the template), tool list with same `{% if %}` guards as RHEL.
- `changelog.template.j2`: no changes needed — copy one existing file as the shared version.

### Todo List
1. Read all `control.template.j2` files for versions 11–26 (JDK) and enumerate the exact `Provides:` lines that differ.
2. Author `linux_v3/jdk/debian/src/main/packaging/temurin/debian/control.template.j2` with `{% set release_num = package_version.split('.')[0] | int %}` at the top.
3. Author `linux_v3/jdk/debian/src/main/packaging/temurin/debian/rules.template.j2` with version-conditional tool list.
4. Copy one `changelog.template.j2` as the shared version (no changes needed).
5. Test render for versions 11, 17, 21, 24 and diff against existing per-version output.
6. Repeat for `jre/debian/`.
7. Delete per-version directories 11–26.
8. Update `templatebase` in the Jenkinsfile (debian block) with the conditional path.

### Relevant Context
- Current Jenkinsfile line (post Sub-Task 1): `templatebase = "./linux_v3/${PTYPE}/${DistArrayElement}/src/main/packaging/${PRODUCT}/${Release}/${DistArrayElement}/${debianFilesArrayElement}.template.j2"`
- `package_version` is always passed as the first positional arg and for non-JDK8 always starts with the major release number (e.g. `17.0.14.0.0+7`).

---

## Sub-Task 8 — Consolidate Alpine APKBUILD templates (versions 11–26)

**Status:** `[ ] pending`

### Intent
The Alpine APKBUILD templates at `linux_v3/jdk/alpine/src/main/packaging/temurin/{11,17,21,23,24,25,26}/alpine.jdk{N}.template.j2` are 103 lines each. Differences across versions 11–26:
- `pkgname` and `_java_home` contain the version number — both derivable from `{{ package_version.split('.')[0] }}` inside the template.
- `provider_priority` is the major version number.
- One `ldpath` line (`$_java_home/lib/jli`) is present in version 11 only — a single `{% if release_num == 11 %}` guard.

Replace 7 JDK + 7 JRE Alpine templates with a single `alpine.jdk.template.j2` and `alpine.jre.template.j2`.

### Expected Outcomes
- `linux_v3/jdk/alpine/src/main/packaging/temurin/alpine.jdk.template.j2` covers versions 11–26.
- `linux_v3/jre/alpine/src/main/packaging/temurin/alpine.jre.template.j2` covers versions 11–26.
- Per-version directories 11–26 under both paths are deleted; `8/` stays.
- Jenkinsfile `templatebase` for alpine uses conditional path (non-8 uses new flat path).
- Rendered output is byte-for-byte identical for all tested versions.

### Todo List
1. Read Alpine JDK templates v11, v17, v21 and confirm the complete list of version-varying lines.
2. Author `linux_v3/jdk/alpine/src/main/packaging/temurin/alpine.jdk.template.j2` using `{% set release_num = package_version.split('_')[0].split('.')[0] | int %}` (Alpine `package_version` uses `_p` notation, e.g. `17.0.14_p7`) to derive `pkgname`, `_java_home`, `provider_priority` and the conditional `ldpath` entry.
3. Test render for versions 11, 17, 21 and diff against existing per-version output.
4. Repeat for `jre/alpine/`.
5. Delete per-version directories 11–26.
6. Update `templatebase` in the Jenkinsfile (alpine block) with the conditional path.

### Relevant Context
- Current Jenkinsfile line (post Sub-Task 1): `templatebase = "./linux_v3/${PTYPE}/${DistArrayElement}/src/main/packaging/${PRODUCT}/${Release}/${DistArrayElement}.${PTYPE}${Release}.template.j2"`
- Alpine `package_version` format differs from RPM/Debian: it uses `_p` as build separator (e.g. `17.0.14_p7` instead of `17.0.14+7`), so the `release_num` extraction uses `.split('_')[0].split('.')[0]`.
