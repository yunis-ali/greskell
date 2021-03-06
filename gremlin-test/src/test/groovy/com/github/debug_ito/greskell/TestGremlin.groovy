package com.github.debug_ito.greskell;

import org.junit.Test;
import static org.junit.Assert.assertThat;
import static org.hamcrest.CoreMatchers.*;
import org.apache.tinkerpop.gremlin.process.traversal.dsl.graph.__;
import org.apache.tinkerpop.gremlin.tinkergraph.structure.TinkerGraph;
import org.apache.tinkerpop.gremlin.structure.Vertex;
import org.apache.tinkerpop.gremlin.structure.Edge;
import org.apache.tinkerpop.gremlin.process.traversal.Order;
import org.apache.tinkerpop.gremlin.process.traversal.P;


public class TestGremlin {
  @Test
  public void filter_resets_traversal() throws Exception {
    def g = MyModern.make().traversal();
    def without_filter = g.V().has("name", "marko").path().toList();
    def with_filter = g.V().has("name", "marko").filter(__.out().out()).path().toList();
    assertThat with_filter, is(without_filter);
  }

  @Test
  public void aggregate_sideEffect_affects_parents() throws Exception {
    def g = MyModern.make().traversal();
    def got_se = g.V().sideEffect(__.sideEffect(__.sideEffect(__.aggregate("x")))).cap("x").next();
    assertThat got_se.size(), is(6);

    def got_fil = g.V().filter(__.filter(__.filter(__.aggregate("x")))).cap("x").next();
    assertThat got_fil.size(), is(6);

    def got_loc = g.V().local(__.local(__.local(__.aggregate("x")))).cap("x").next();
    assertThat got_loc.size(), is(6);
  }

  @Test
  public void GTraversal_is_not_Category() throws Exception {
    def g = MyModern.make().traversal();
    def a = { g.V() };
    def b = { __.identity() };
    def ab = a().repeat(b()).times(1).toList();
    def ba = b().repeat(a()).times(1).toList();
    assertThat ab, is(not(ba));
  }

  @Test
  public void as_is_cancalled_in_splitting_traversal() throws Exception {
    def g = MyModern.make().traversal();
    assertThat g.V().as("x").out().as("y").select("x").toList().size(), is(6);
    assertThat g.V().as("x").out().as("y").select("y").toList().size(), is(6);
    assertThat g.V().sideEffect(__.as("x").out().as("y")).select("x").toList().size(), is(0);
    assertThat g.V().sideEffect(__.as("x").out().as("y")).select("y").toList().size(), is(0);
    assertThat g.V().filter(__.as("x").out().as("y")).select("x").toList().size(), is(0);
    assertThat g.V().filter(__.as("x").out().as("y")).select("y").toList().size(), is(0);
    
    assertThat g.V().map(__.as("x").out().as("y")).select("x").toList().size(), is(0);
    assertThat g.V().flatMap(__.as("x").out().as("y")).select("x").toList().size(), is(0);
  }

  @Test
  public void flatMap_map_affect_path() throws Exception {
    def g = MyModern.make().traversal();
    assertThat g.V().map(__.identity()).path().next().size(), is(2);
    assertThat g.V().flatMap(__.identity()).path().next().size(), is(2);
  }

  @Test
  public void flatMap_map_cancel_child_travasal_paths() throws Exception {
    def g = MyModern.make().traversal();
    assertThat g.V().out().in().out().in().path().next().size(), is(5);
    assertThat g.V().map(__.out().in().out().in()).path().next().size(), is(2);
    assertThat g.V().flatMap(__.out().in().out().in()).path().next().size(), is(2);
  }

  @Test
  public void order_by_projection_traversal_uses_the_first_element() throws Exception {
    def graph = TinkerGraph.open();
    def g = graph.traversal();
    g.addV("target").property("name","A")
    .addV("target").property("name","B")
    .addV("valA").property("v",10)
    .addV("valA").property("v",20)
    .addV("valA").property("v",30)
    .addV("valB").property("v",5)
    .addV("valB").property("v",15)
    .addV("valB").property("v",25)
    .addV("valB").property("v",35)
    .addV("valB").property("v",45).iterate();
    g.V().hasLabel("target").has("name","A").as("target_A").V().hasLabel("valA").addE("has_value").from("target_A").iterate();
    g.V().hasLabel("target").has("name","B").as("target_B").V().hasLabel("valB").addE("has_value").from("target_B").iterate();
    assertThat g.V().hasLabel("target").has("name","A").out().values("v").order().by(Order.incr).toList(), is([10,20,30]);
    assertThat g.V().hasLabel("target").has("name","B").out().values("v").order().by(Order.incr).toList(), is([5,15,25,35,45]);

    assertThat g.V().hasLabel("target").order().by(__.out().values("v").order().by(Order.incr), Order.incr).values("name").toList(), is(["B", "A"]);
    assertThat g.V().hasLabel("target").order().by(__.out().values("v").order().by(Order.decr), Order.incr).values("name").toList(), is(["A", "B"]);
  }

  @Test
  public void path_by_projection_traversal_uses_the_first_element() throws Exception {
    def g = MyModern.make().traversal();
    assertThat g.V().has("name", "marko").path().by("name")
               .map({ it.get().objects() }).toList(), is([["marko"]]);
    assertThat g.V().has("name", "marko").path().by(__.outE("knows").order().by("weight",Order.decr).inV().values("name"))
               .map({ it.get().objects() }).toList(), is([["josh"]]);
  }

  @Test
  public void addE_traversal_takes_input_to_addE() throws Exception {
    def g = MyModern.make().traversal();
    def edges = g.V().has("name", P.within("marko", "peter", "josh"))
                .addE("new_edge").from(__.outE("created").order().by("weight", Order.incr).inV()).toList();
    // The traversal inside .from() yields 2 anchor vertices for
    // "josh" (namely, "lop" and "ripple"), but only the first vertex
    // is used for the anchor. As a result, .addE() always creates
    // exactly one edge for each input Vertex.
    assertThat edges.size(), is(3);
    edges.each { e ->
      assertThat((e instanceof Edge), is(true));
      assertThat(e.label(), is("new_edge"));
    };
    def pairs = edges.collect { e -> return (String)(e.outVertex().value("name")) + "->" + (String)(e.inVertex().value("name")) };
    assertThat pairs.sort(), is(["lop->josh", "lop->marko", "lop->peter"]);
    assertThat(g.E().hasLabel("new_edge").toList().size(), is(3));
  }

  @Test
  public void addE_traversal_throws_error_if_it_yields_no_result() throws Exception {
    def g = MyModern.make().traversal();
    try {
      g.V().has("name", "vadas").addE("new_edge").from(__.out("created")).iterate();
      fail("this operation is supposed to throw an exception");
    }catch(Exception e) {
      // expected.
      ;
    }
  }

  @Test
  public void V_method_flatMaps_the_input_traverser() throws Exception {
    def g = MyModern.make().traversal();
    def paths = g.E().hasLabel("created").outV().as("creator").V().has("name", P.within("vadas", "ripple")).path().toList();
    def paths_str = paths.collect { p ->
      p.objects().collect { elem ->
        if(elem instanceof Vertex) {
          return "v(" + (String)(((Vertex)elem).value("name")) + ")";
        }else if(elem instanceof Edge) {
          def e = (Edge)elem;
          return "e(" + (String)e.outVertex().value("name") + "-" + e.label() + "->" +
            (String)e.inVertex().value("name") + ")";
        }
      }.join(",");
    };
    assertThat paths_str.sort(), is([
      "e(josh-created->lop),v(josh),v(ripple)",
      "e(josh-created->lop),v(josh),v(vadas)",
      "e(josh-created->ripple),v(josh),v(ripple)",
      "e(josh-created->ripple),v(josh),v(vadas)",
      "e(marko-created->lop),v(marko),v(ripple)",
      "e(marko-created->lop),v(marko),v(vadas)",
      "e(peter-created->lop),v(peter),v(ripple)",
      "e(peter-created->lop),v(peter),v(vadas)",
     ]);
  }
}
