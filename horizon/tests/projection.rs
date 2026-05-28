//! Projection test — the schema-emitted `ClusterProposal` projects.
//!
//! Constructs a real collection-bearing `ClusterProposal` (a map of
//! nodes, a list of services, an optional binary cache, the imported
//! `Magnitude` trust), runs the projection method, and asserts the
//! per-node `Output::Projected` map. Also exercises the NOTA round-trip
//! of the collection-bearing input and the rkyv archive — proving the
//! emitted collection codec works end to end on the Horizon domain.

use std::collections::BTreeMap;

use horizon_core::schema::magnitude::Magnitude;
use horizon_next::schema::horizon::{
    BinaryCache, CacheUrl, ClusterProposal, ClusterTrust, Input, NodeName, NodeProposal, NodeRole,
    Output, ServiceName,
};

fn node(role: NodeRole, trust: Magnitude, services: &[&str]) -> NodeProposal {
    NodeProposal {
        role,
        trust,
        services: services
            .iter()
            .map(|name| ServiceName(String::from(*name)))
            .collect(),
    }
}

fn sample_cluster() -> ClusterProposal {
    let mut nodes = BTreeMap::new();
    nodes.insert(
        NodeName(String::from("center")),
        node(NodeRole::Center, Magnitude::High, &["dns"]),
    );
    nodes.insert(
        NodeName(String::from("edge")),
        node(NodeRole::Edge, Magnitude::Low, &["vpn"]),
    );
    // A distrusted node — must be dropped from the projection.
    nodes.insert(
        NodeName(String::from("ghost")),
        node(NodeRole::Builder, Magnitude::Zero, &["build"]),
    );
    ClusterProposal {
        nodes,
        trust: ClusterTrust(Magnitude::Medium),
        cache: Some(BinaryCache(CacheUrl(String::from("https://cache.example")))),
        cluster_services: vec![ServiceName(String::from("ntp"))],
    }
}

#[test]
fn projection_drops_distrusted_nodes_and_keeps_trusted_ones() {
    let cluster = sample_cluster();
    let Output::Projected(configs) = cluster.project() else {
        panic!("a cluster with trusted nodes should project");
    };

    // The distrusted "ghost" node is gone; center + edge remain.
    assert_eq!(configs.len(), 2);
    assert!(configs.contains_key(&NodeName(String::from("center"))));
    assert!(configs.contains_key(&NodeName(String::from("edge"))));
    assert!(!configs.contains_key(&NodeName(String::from("ghost"))));
}

#[test]
fn projected_node_merges_cluster_services_and_inherits_cache() {
    let cluster = sample_cluster();
    let Output::Projected(configs) = cluster.project() else {
        panic!("should project");
    };
    let center = configs
        .get(&NodeName(String::from("center")))
        .expect("center projected");

    // Cluster-wide "ntp" merged ahead of the node's own "dns".
    assert_eq!(
        center.services,
        vec![
            ServiceName(String::from("ntp")),
            ServiceName(String::from("dns")),
        ]
    );
    // The node inherited the cluster's binary-cache URL.
    assert_eq!(
        center.cache,
        Some(CacheUrl(String::from("https://cache.example")))
    );
    // The imported Magnitude rode through projection unchanged.
    assert_eq!(center.trust, Magnitude::High);
}

#[test]
fn empty_cluster_is_rejected() {
    let cluster = ClusterProposal {
        nodes: BTreeMap::new(),
        trust: ClusterTrust(Magnitude::Min),
        cache: None,
        cluster_services: Vec::new(),
    };
    assert!(matches!(cluster.project(), Output::Rejected(_)));
}

#[test]
fn all_distrusted_cluster_is_rejected() {
    let mut nodes = BTreeMap::new();
    nodes.insert(
        NodeName(String::from("ghost")),
        node(NodeRole::Edge, Magnitude::Zero, &[]),
    );
    let cluster = ClusterProposal {
        nodes,
        trust: ClusterTrust(Magnitude::Min),
        cache: None,
        cluster_services: Vec::new(),
    };
    assert!(matches!(cluster.project(), Output::Rejected(_)));
}

#[test]
fn cluster_proposal_round_trips_through_nota() {
    let cluster = sample_cluster();
    let input = Input::Project(cluster.clone());
    let nota = input.to_nota();
    let parsed: Input = nota.parse().expect("input round-trips through nota");
    let Input::Project(parsed_cluster) = parsed;
    assert_eq!(parsed_cluster, cluster);
}

#[test]
fn cluster_proposal_archives_through_rkyv() {
    let cluster = sample_cluster();
    let bytes = rkyv::to_bytes::<rkyv::rancor::Error>(&cluster).expect("archive cluster");
    let decoded =
        rkyv::from_bytes::<ClusterProposal, rkyv::rancor::Error>(&bytes).expect("decode cluster");
    assert_eq!(decoded, cluster);
}

#[test]
fn projection_output_signal_frame_round_trips() {
    let cluster = sample_cluster();
    let output = cluster.project();
    let frame = output.encode_signal_frame().expect("encode output frame");
    let (route, decoded) = Output::decode_signal_frame(&frame).expect("decode output frame");
    assert_eq!(route, horizon_next::schema::horizon::OutputRoute::Projected);
    assert_eq!(decoded, output);
}
