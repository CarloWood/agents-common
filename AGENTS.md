$PLANROOT is the root of a git repository containing the plan for a project in $REPOROOT.

The directory structure in $PLANROOT reflects a plan, where every directory in
$PLANROOT/ObjectiveTree corresponds with a plan node.

# Manipulation rule

The plan must be manipulated using the provided bash functions whose names start
with `aap-`.

Use these helpers to:

- add or remove directories from `$PLANROOT/ObjectiveTree`;
- add or change files named `status`, `description`, `mode`, or `topics`;
- move or update symbolic links that belong to the plan.

Do not manually add, delete, or retarget plan symbolic links, most notably `id`,
`current`, and `current_objective`, unless the relevant helper command explicitly
does that operation.

# Available `aap-*` helpers

The usage text of these helpers use the following convention:

- <node> corresponds to the name of a directory in $PLANROOT/ObjectiveTree, which
typically begin with two digits and a hyphen. For example: `02-preserve-topics-on-no-match`.

- <ref> is a string that uniquely identifies a <node> among the siblings of the current goal,
by matching the beginning thereof. Usually the starting digits.

- <refpath> uniquely identifies a <node> anywhere in the plan tree. It must begin
with a `/` followed by zero or more `<ref>` identifiers. For example: `/02/01`.

## `aap-ls [--fix|--no-fix] [--help]`

Print an overview of the current objective and its parent.

Options:

- `--fix`: apply fixes. This is the default (except for the analyst agent).
- `--no-fix`: only report problems; do not modify the ObjectiveTree or symlinks.

## `aap-insert [--parent <refpath>] <node>`

Insert a new leaf goal node and set it as `current_objective`.

The description is read from stdin.

If `--parent` is not given, the new `<node>` must lexicographically be ordered
immediately before the current objective, as shown by `aap-ls`.

If `--parent` is given, the new `<node>` is added to that parent.
Use `--parent /` to add a new `<node>` to `ObjectiveTree` itself.

## `aap-configure [<cmake args>...]`

Configure the current project into the planner-specific build directory.

Only use this when `$REPOROOT` uses CMake.

## `aap-build [<cmake --build args>...]`

Build the current project from the planner-specific build directory.

Only use this when `$REPOROOT` uses CMake.

## `aap-done <ref>`

Mark the current objective as achieved, then update `current_objective` to the
lexicographically first not-achieved <node>.

<ref> must match the current objective.

## `aap-previous`

Move `current_objective` to the previous goal in depth-first lexicographic order and mark it not-achieved.

Normally this is only used when the user specifically asks to revisit the
previous objective or goal because it was marked done by mistake.

# PLANROOT directory structure

## Objective/Goal Tree

The root directory of the plan tree is:

`$PLANROOT/ObjectiveTree/`

The objective/goal tree is collectively called the plan.

The tree is represented by a filesystem tree where each directory is a plan node.
A plan node is an objective with respect to its child goals, and a goal with
respect to its parent objective.

Thus, every non-root, non-leaf node is both a goal of its parent and the objective
for its own children.

The tree is recursive and uniform; conceptually the same rules apply at every
node.

## Required contents of every plan node

Every plan node must contain:

- a file named `description`;
- a file named `status`.

It may also contain:

- child goal directories;
- other reserved metadata files defined by this specification.

No unstructured notes or ad hoc files may be placed in a plan node directory
unless explicitly allowed by this specification.

## Meaning of the required files

- `description` defines the objective represented by that directory.
- `status` records whether that node has been achieved.

Child goal directories represent the ordered goals that contribute to achieving
the objective described by the parent directory.

## Current objective

The current objective is the target of the symbolic link:

`$PLANROOT/current_objective`

This symlink must point to one of the <node> directories.

Therefore, the description of the current objective is always:

`$PLANROOT/current_objective/description`

## Goal ordering

The child goal directories of an objective are ordered.

Their order is determined by their directory names. Goal directory names must
therefore begin with a numeric ordering prefix of two digits:

```text
01-...
02-...
03-...
```

Lexical order defines plan order.

Earlier goals are normally addressed before later goals.

This numeric prefix may be used by the user to identify the goal. A goal can be
inserted either by renaming the numeric prefixes that follow it, or by choosing a
directory name that lexicographically inserts the node at the right position.

For example:

```text
02-...
02.5-...     inserted
03-...
```

## Example

```text
ObjectiveTree/
  01-define-scope/
    description
    status
  02-build-harness/
    description
    status
  03-run-benchmarks/
    01-benchmark-inversion/
      description
      status
    02-benchmark-composition/
      description
      status
    description
    status
```

In this example, `03-run-benchmarks/` is a primary goal (of `ObjectiveTree/`),
but also an objective for its own child goals.

## Default dependency rule

By default, each goal depends on all earlier sibling goals.

This means that, unless explicitly specified otherwise, a goal should not be
worked on by the coder until all preceding sibling goals have been achieved.

If this default does not apply, record the exception in a reserved metadata file
defined elsewhere in this specification.

Hence, if `current_objective` points to any directory in an ordered tree listing
as shown in the example, then every `status` file above it will typically contain
`achieved` and all files below it will typically contain `not-achieved`.

## Invariants

- Every objective or goal is a directory, called a plan node.
- Every plan node directory must contain `description` and `status`.
- Every child directory of a plan node is a goal of that node.
- The `description` file defines the objective of the node itself, not of its parent.
- The `status` file defines whether that node, as a goal of its parent, has been achieved.
- Child goals must be ordered by names that start with two digits.
- The tree structure itself is the canonical source of truth.
- Derived summaries or helper scripts may be used for navigation, but must not replace the tree as the authoritative representation.

## Format of a description file

The `description` file in each plan node directory states the objective of that
node.

It must:

- describe the intended outcome clearly and precisely;
- be self-contained;
- be concise;
- be written as an objective, not as a task list;
- describe the effects of the to-be-written code or patch, optionally including
  example scenarios, how to verify it works, likely files or functions to change,
  and why the objective matters, but without including actual code;
- be short enough that a human can read and agree or disagree within a few seconds.

It must not:

- list child goals;
- record status;
- contain implementation notes or discussion unless strictly needed to understand
  the objective.

A `description` file should normally contain a short paragraph.

Example:

```text
Implement a benchmark suite for the most common transform operations so that performance can be measured reproducibly and compared across implementations.
```

## Format of a status file

The `status` file in each plan node directory records whether that node has been
achieved.

Its content must be exactly one of:

- `not-achieved`
- `achieved`

No other text is allowed.
