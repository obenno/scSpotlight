export const ScatterLifecycleState = Object.freeze({
  IDLE: "idle",
  MOUNTING: "mounting",
  READY: "ready",
  RESIZING: "resizing",
  CLEARING: "clearing",
});

export class ScatterLifecycle {
  constructor() {
    this.state = ScatterLifecycleState.IDLE;
  }

  setIdle() {
    this.state = ScatterLifecycleState.IDLE;
  }

  setMounting() {
    this.state = ScatterLifecycleState.MOUNTING;
  }

  setReady() {
    this.state = ScatterLifecycleState.READY;
  }

  setResizing() {
    this.state = ScatterLifecycleState.RESIZING;
  }

  setClearing() {
    this.state = ScatterLifecycleState.CLEARING;
  }

  isReady() {
    return this.state === ScatterLifecycleState.READY;
  }

  isResizing() {
    return this.state === ScatterLifecycleState.RESIZING;
  }

  isMounting() {
    return this.state === ScatterLifecycleState.MOUNTING;
  }
}
