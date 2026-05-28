use std::{env, fs, path::PathBuf};

use schema_next::{MacroContext, Name, SchemaEngine, SchemaPackage};
use schema_rust_next::{GeneratedFile, RustEmitter};

fn main() {
    SchemaBuild::from_environment().run();
}

/// The shared-schema crate's build: lower `schema/magnitude.schema` to
/// checked-in Rust, then advertise the schema directory to dependents
/// through Cargo's `links` metadata so a `DEP_HORIZON_CORE_SCHEMA_DIR`
/// env var reaches each direct dependent's build script. Mirrors the
/// proven schema-core mechanism (record /39).
struct SchemaBuild {
    crate_root: PathBuf,
}

impl SchemaBuild {
    fn from_environment() -> Self {
        Self {
            crate_root: PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("manifest dir set")),
        }
    }

    fn run(&self) {
        println!("cargo:rerun-if-changed=schema/magnitude.schema");
        println!("cargo:rerun-if-changed=src/schema/magnitude.rs");

        let generated = self.generated_module("magnitude");
        if env::var_os("HORIZON_REGENERATE_SCHEMA").is_some() {
            let checked_in = CheckedInSchemaSource::new(&self.crate_root, &generated);
            fs::write(checked_in.path(), checked_in.expected_source())
                .expect("write regenerated schema source");
        } else {
            self.assert_checked_in_schema_is_fresh(&generated);
        }
        self.advertise_schema_directory();
    }

    /// Emit `cargo::metadata=schema-dir=<root>/schema`. Cargo turns the
    /// `schema-dir` metadata key of a `links`-declaring crate into the
    /// `DEP_HORIZON_CORE_SCHEMA_DIR` environment variable for every
    /// direct dependent's build script — the cross-crate seam.
    fn advertise_schema_directory(&self) {
        let schema_directory = self.crate_root.join("schema");
        println!("cargo::metadata=schema-dir={}", schema_directory.display());
    }

    fn generated_module(&self, module: &str) -> GeneratedFile {
        let mut context = MacroContext::default();
        let package = SchemaPackage::new(&self.crate_root, "horizon-core", "0.1.0");
        let source = package
            .load_module(Name::new(module))
            .unwrap_or_else(|error| panic!("read schema/{module}.schema: {error}"));
        let asschema = SchemaEngine::default()
            .lower_source_with_context(source.source(), source.identity().clone(), &mut context)
            .unwrap_or_else(|error| panic!("lower horizon-core {module} schema: {error}"));
        RustEmitter::default().emit_file(&asschema)
    }

    fn assert_checked_in_schema_is_fresh(&self, generated: &GeneratedFile) {
        let checked_in = CheckedInSchemaSource::new(&self.crate_root, generated);
        let actual = fs::read_to_string(checked_in.path()).unwrap_or_else(|error| {
            panic!(
                "checked-in generated schema source is missing at {}: {error}",
                checked_in.path().display()
            )
        });
        if actual != checked_in.expected_source() {
            panic!(
                "checked-in generated schema source is stale at {}; regenerate it from schema/magnitude.schema",
                checked_in.path().display()
            );
        }
    }
}

struct CheckedInSchemaSource<'schema> {
    crate_root: &'schema PathBuf,
    generated: &'schema GeneratedFile,
}

impl<'schema> CheckedInSchemaSource<'schema> {
    fn new(crate_root: &'schema PathBuf, generated: &'schema GeneratedFile) -> Self {
        Self {
            crate_root,
            generated,
        }
    }

    fn path(&self) -> PathBuf {
        self.crate_root.join(&self.generated.path)
    }

    fn expected_source(&self) -> String {
        self.generated.code.as_str().to_owned()
    }
}
