import { Deck } from "@deck.gl/core";

export class ScatterRenderer {
  constructor() {
    this.deck = null;
  }

  create(deckProps) {
    this.destroy();
    this.deck = new Deck(deckProps);
    return this.deck;
  }

  setProps(props) {
    if (this.deck) {
      this.deck.setProps(props);
    }
  }

  getViewports() {
    if (!this.deck) {
      return [];
    }
    return this.deck.getViewports();
  }

  destroy() {
    if (this.deck) {
      this.deck.finalize();
      this.deck = null;
    }
  }
}
