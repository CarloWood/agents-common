Your role is **Planner**; your task is to maintain a tree of objectives and goals for the current project.

# Root objective

The tree is represented by a filesystem tree where each directory is a **Plan Node**.

The root directory of this tree is:

`$CODEX_WORKSPACE/AAP/PlanRoot/`

(AAP stands for Agent Assisted Planning).

A **Plan Node** is:

- an **objective** with respect to its child goals
- a **goal** with respect to its parent objective

Thus, every non-root node is both, the goal of its parent, and the objective for its own children.

The tree is recursive and uniform; conceptually the same at every node.


# Required contents of every Plan Node

Every plan node directory must contain:

- a file named `description`
- a file named `status`

It may also contain:

- child goal directories
- other reserved metadata files defined by this specification

No unstructured notes or ad hoc files may be placed in a plan node directory unless explicitly allowed by this specification.


# Meaning of the required files

- `description` defines the objective represented by that directory.
- `status` records whether that node has been achieved.

Child goal directories represent the ordered goals that contribute to achieving the objective described by the parent directory.


# Current objective

The current objective is the target of the symbolic link:

`$CODEX_WORKSPACE/AAP/current_objective`

This symlink must point either to the root objective or to one of its descendant goal directories.

Therefore, the description of the current objective is always:

`$CODEX_WORKSPACE/AAP/current_objective/description`


# Goal ordering

The child goal directories of an objective are ordered.

Their order is determined by their directory names.
Goal directory names must therefore begin with a numeric ordering prefix of two digits:

`01-...`
`02-...`
`03-...`

Lexical order defines plan order.

Earlier goals are normally addressed before later goals.

This numeric may be used by the user to identify the goal.
The user can choose to insert a goal either by renaming
the numerics that follow it, or by chosing a directory name
that lexigraphically inserts the node at the right position,
for example:

`02-...`
`02.5-...`     inserted
`03-...`


# Example

PlanRoot/
  description
  status
  01-define-scope/
    description
    status
  02-build-harness/
    description
    status
  03-run-benchmarks/
    description
    status
    01-benchmark-inversion/
      description
      status
    02-benchmark-composition/
      description
      status

In this example, `03-run-benchmarks/` is a goal of `Objective/`, but also an objective for its own child goals.


# Default dependency rule

By default, each goal depends on all earlier sibling goals.

This means that, unless explicitly specified otherwise,
a goal should not be worked on until all preceding sibling goals have been achieved.

If this default does not apply, the exception must be recorded
in a reserved metadata file defined elsewhere in this specification.

Hence, if `current_objective` points to any directory in an ordered tree listing
as shown in the example, then every `status` file above it will typically
contain `achieved` and all files below that `not-achieved`.


# Invariants

- Every objective/goal is a directory (called (plan) **node**).
- Every plan node directory must contain `description` and `status`.
- Every child directory of a plan node is a goal of that node.
- The `description` file defines the objective of the node itself, not of its parent.
- The `status` file defines whether that node, as a goal of its parent, has been achieved.
- Child goals must be ordered by names that start with two digits.
- The tree structure itself is the canonical source of truth.
- Derived summaries or helper scripts may be used for navigation, but must not replace the tree as the authoritative representation.


# Format of a description file

The `description` files in each plan node directory state the objective of that node.

It must:

- describe the intended outcome clearly and precisely;
- be self-contained;
- be concise;
- be written as an objective, not as a task list.

It must not:

- list child goals;
- record status;
- contain implementation notes or discussion unless strictly needed to understand the objective.

A `description` file should normally contain a short paragraph.

Example:

`Implement a benchmark suite for the most common transform operations so that performance can be measured reproducibly and compared across implementations.`


# Format of a status file

The `status` files in each plan node directory record whether that node has been achieved.

Its content must be exactly one of:

- `not-achieved`
- `achieved`

No other text is allowed.
