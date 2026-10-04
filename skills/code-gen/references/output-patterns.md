# Code Generation Output Patterns

## Before Generating

1. If the request is ambiguous, ask one focused clarifying question — don't guess.
2. Check what already exists in the repo for patterns to follow and code to reuse.
3. Identify the target language from file extension or explicit instruction.
4. Check if a `tasks.md` exists — if so, read it and continue from the first unchecked task.

## Output Structure

### New function or method
Present in this order:
1. Implementation with type hints (Python) or types (TypeScript)
2. If tests were requested: test class/suite after the implementation

### New class or module
Present in this order:
1. Imports
2. Constants / config (if any)
3. Class body — public interface first, private helpers below
4. No more than one public class per file

### Test files (Python)
Follow `python-guidelines.md`:
1. `setUpClass` / `setUp` at top
2. Test methods grouped by the function under test
3. One assertion per test where possible (or tight related assertions)

### `__init__.py` files
- Default: completely empty (no content, no comments)
- Only add exports when the package has a deliberate public API

## What to Include

- Only the code that was asked for
- Import statements needed by the generated code
- `tasks.md` updates for medium/large tasks

## What to Exclude

- README files or markdown docs
- `if __name__ == '__main__':` blocks in test files
- Placeholder `# TODO` comments
- Commented-out code
- Docstrings on simple/obvious methods
- Extra helper classes or utilities unless explicitly requested
