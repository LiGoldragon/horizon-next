//! The running three-engine chain (records 1028 / 1030 / 1054).
//!
//! This is the D4 witness: a real Horizon projection request is driven
//! end to end through all three trait-ordered engines, matching directly
//! on the data-carrying `Plane` enum (record 1054 — the variants carry
//! the actual plane messages; no thin kind tag beside an envelope, which
//! record 1052 names wrong). The origin route minted at ingress (records
//! 1038/1039) threads every hop and is echoed on the reply Plane.
//!
//! Per `skills/testing.md` §"Per-plane chain typing", the test exercises
//! each engine's trait surface with the right `Plane`-carried message and
//! makes every plane crossing VISIBLE — Signal admits onto the Nexus
//! plane, Nexus executes onto the Sema plane, Sema applies and returns
//! the reply. It does not collapse the crossings into one opaque call.

use std::collections::BTreeMap;

use horizon_core::schema::magnitude::Magnitude;
use horizon_next::schema::horizon::{
    BinaryCache, CacheUrl, ClusterProposal, ClusterTrust, Input, NexusEngine, NodeName,
    NodeProposal, NodeRole, OriginRoute, Output, Plane, ServiceName, SignalEngine,
};
use horizon_next::{ProjectionNexus, ProjectionSema, SignalGate};

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
    // A distrusted node — must be dropped during Nexus execution.
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
fn request_drives_signal_then_nexus_then_sema_and_echoes_origin_route() {
    // Mint the origin route at ingress and wrap the request as the
    // Signal-plane root of the Plane enum (record 1054 + 1038/1039).
    let ingress_route = OriginRoute::at_ingress(42);
    let ingress = Plane::at_ingress(ingress_route, Input::Project(sample_cluster()));
    assert!(matches!(ingress, Plane::Signal(_, _)));
    assert_eq!(ingress.origin_route(), ingress_route);

    let signal = SignalGate::new();
    let nexus = ProjectionNexus::new();
    let mut sema = ProjectionSema::new();

    // Drive the request through all three engines. `Plane::drive` is the
    // schema-emitted running chain: Signal -> Nexus -> Sema -> reply.
    let reply = ingress
        .drive(&signal, &nexus, &mut sema)
        .expect("the request drives cleanly through the three-engine chain");

    // The reply lands on the Sema plane carrying the projected Output,
    // and the origin route minted at ingress is echoed back unchanged.
    let Plane::Sema(reply_route, Output::Projected(configs)) = reply else {
        panic!("the chain should reply with a Sema-plane projected output");
    };
    assert_eq!(reply_route, ingress_route);

    // The projection ran for real inside the Nexus engine: the distrusted
    // "ghost" node was dropped; center + edge remain.
    assert_eq!(configs.len(), 2);
    assert!(configs.contains_key(&NodeName(String::from("center"))));
    assert!(!configs.contains_key(&NodeName(String::from("ghost"))));

    // The Sema engine applied the reply to durable state: its last
    // projection is the configs map, and it counted one application.
    assert_eq!(sema.applied_count(), 1);
    assert_eq!(sema.last_projection(), &configs);
}

#[test]
fn each_plane_crossing_is_visible_and_typed() {
    // The same chain, but driven engine-by-engine so each plane crossing
    // is explicit (the chain-typing discipline of skills/testing.md).
    let ingress_route = OriginRoute::at_ingress(7);
    let signal_plane = Plane::Signal(ingress_route, Input::Project(sample_cluster()));

    // Crossing 1: Signal -> Nexus. The Signal engine admits the request
    // onto the Nexus plane, carrying the same origin route.
    let signal = SignalGate::new();
    let nexus_plane = signal
        .admit(signal_plane)
        .expect("signal admits the request");
    let Plane::Nexus(route_after_signal, _) = &nexus_plane else {
        panic!("signal must hand the request onto the Nexus plane");
    };
    assert_eq!(*route_after_signal, ingress_route);

    // Crossing 2: Nexus -> Sema. The Nexus engine executes the projection
    // and hands the reply onto the Sema plane.
    let nexus = ProjectionNexus::new();
    let sema_plane = nexus
        .execute(nexus_plane)
        .expect("nexus executes the projection");
    let Plane::Sema(route_after_nexus, Output::Projected(_)) = &sema_plane else {
        panic!("nexus must produce a Sema-plane projected output");
    };
    assert_eq!(*route_after_nexus, ingress_route);

    // Crossing 3: Sema applies and returns the reply Plane.
    let mut sema = ProjectionSema::new();
    use horizon_next::schema::horizon::SemaEngine;
    let reply = sema.apply(sema_plane).expect("sema applies the reply");
    assert_eq!(reply.origin_route(), ingress_route);
    assert_eq!(sema.applied_count(), 1);
}

#[test]
fn signal_engine_rejects_an_empty_cluster_before_projection() {
    // The Signal admission gate rejects a structurally-empty request, so
    // the chain never reaches Nexus or Sema.
    let empty = ClusterProposal {
        nodes: BTreeMap::new(),
        trust: ClusterTrust(Magnitude::Min),
        cache: None,
        cluster_services: Vec::new(),
    };
    let ingress = Plane::at_ingress(OriginRoute::at_ingress(1), Input::Project(empty));

    let signal = SignalGate::new();
    let nexus = ProjectionNexus::new();
    let mut sema = ProjectionSema::new();

    let outcome = ingress.drive(&signal, &nexus, &mut sema);
    assert!(
        outcome.is_err(),
        "an empty cluster is rejected at the Signal gate"
    );
    // Sema never ran, so its durable state stays empty.
    assert_eq!(sema.applied_count(), 0);
}
