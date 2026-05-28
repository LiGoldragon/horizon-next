use std::{env, fs, path::PathBuf};

use schema_next::{ImportResolver, MacroContext, Name, SchemaEngine, SchemaPackage};
use schema_rust_next::{GeneratedFile, RustEmitter};

fn main() {
    SchemaBuild::from_environment().run();
}

/// The Horizon concept's build: resolve the cross-crate import of
/// `horizon-core:magnitude:Magnitude` against the schema directory
/// Cargo exposed for the `horizon-core` dependency, then lower
/// `schema/horizon.schema` to checked-in Rust at `src/schema/horizon.rs`
/// — collection-bearing `ClusterProposal` / `NodeProposal` referencing
/// the dependency crate's `Magnitude` instead of re-declaring it.
struct SchemaBuild {
    crate_root: PathBuf,
    dependency_schema_dir: PathBuf,
}

impl SchemaBuild {
    /// Read `DEP_HORIZON_CORE_SCHEMA_DIR` — the env var Cargo sets for a
    /// direct dependent of the `links = "horizon-core"` crate, carrying
    /// the `schema-dir` metadata that crate's build script emitted. Its
    /// presence is the cross-crate seam working; its absence is a hard
    /// build error, because the import cannot resolve without it.
    fn from_environment() -> Self {
        let crate_root =
            PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("manifest dir set"));
        let dependency_schema_dir =
            PathBuf::from(env::var_os("DEP_HORIZON_CORE_SCHEMA_DIR").expect(
                "DEP_HORIZON_CORE_SCHEMA_DIR set by Cargo for the horizon-core links dependency",
            ));
        Self {
            crate_root,
            dependency_schema_dir,
        }
    }

    fn run(&self) {
        println!("cargo:rerun-if-changed=schema/horizon.schema");
        println!("cargo:rerun-if-changed=src/schema/horizon.rs");

        let generated = self.generated_schema_file();
        self.assert_generated_schema_path(&generated);
        self.assert_checked_in_schema_is_fresh(&generated);
    }

    fn import_resolver(&self) -> ImportResolver {
        ImportResolver::new().with_dependency(
            "horizon-core",
            self.dependency_schema_dir.clone(),
            "0.1.0",
        )
    }

    fn generated_schema_file(&self) -> GeneratedFile {
        let mut context = MacroContext::default();
        let package = SchemaPackage::new(&self.crate_root, "horizon-next", "0.1.0");
        let source = package
            .load_module(Name::new("horizon"))
            .expect("read schema/horizon.schema");
        let asschema = SchemaEngine::default()
            .lower_source_with_resolver(
                source.source(),
                source.identity().clone(),
                &mut context,
                &self.import_resolver(),
            )
            .expect("lower horizon schema with resolved cross-crate import");
        RustEmitter::default().emit_file(&asschema)
    }

    fn assert_generated_schema_path(&self, generated: &GeneratedFile) {
        if generated.path.as_str() != "src/schema/horizon.rs" {
            panic!(
                "horizon schema must emit src/schema/horizon.rs, found {}",
                generated.path
            );
        }
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
                "checked-in generated schema source is stale at {}; regenerate it from schema/horizon.schema",
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
