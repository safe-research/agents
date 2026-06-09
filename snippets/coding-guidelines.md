## Coding Guidelines

Code SHOULD focus on security and maintainability. Existing code and components SHOULD be reused. New components SHOULD be written in a way that they can be reused. Refer to existing code to determine coding style and which implementation to choose. Do not re-invent the wheel and follow existing paradigms.

You MUST format, lint and test before committing.

- For JavaScript/Typescript code, run `npm run fix`, `npm run check`, and `npm test` respectively (you SHOULD include the `--workspace <package>` flag to the NPM commands if working on a workspace package in a monorepo)
- For Rust code, run `cargo fmt --all`, `cargo clippy`, and `cargo test` respectively (you SHOULD include the `--package <package>` flag to the `clippy` and `test` commands if working on a workspace create in a monorepo)
