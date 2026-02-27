import { describe, expect, it } from "vitest";
import { ScatterLifecycle, ScatterLifecycleState } from "./scatterLifecycle.js";

describe("ScatterLifecycle", () => {
  it("starts in idle and transitions through states", () => {
    const life = new ScatterLifecycle();
    expect(life.state).toBe(ScatterLifecycleState.IDLE);

    life.setMounting();
    expect(life.state).toBe(ScatterLifecycleState.MOUNTING);
    expect(life.isMounting()).toBe(true);

    life.setReady();
    expect(life.state).toBe(ScatterLifecycleState.READY);
    expect(life.isReady()).toBe(true);

    life.setResizing();
    expect(life.state).toBe(ScatterLifecycleState.RESIZING);
    expect(life.isResizing()).toBe(true);

    life.setClearing();
    expect(life.state).toBe(ScatterLifecycleState.CLEARING);

    life.setIdle();
    expect(life.state).toBe(ScatterLifecycleState.IDLE);
  });
});
