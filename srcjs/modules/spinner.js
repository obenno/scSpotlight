export const initFullScreenSpinner = (text) => {
  const el = document.createElement("div");
  el.classList.add("loading-overlay");

  const container = document.createElement("div");
  container.classList.add("spinner-container");

  const sp = document.createElement("div");
  sp.classList.add("bounce-spinner");

  const child1 = document.createElement("div");
  child1.classList.add("double-bounce1");
  const child2 = document.createElement("div");
  child2.classList.add("double-bounce2");

  const textEl = document.createElement("div");
  textEl.classList.add("spinner-text");
  textEl.innerHTML = text;

  sp.appendChild(child1);
  sp.appendChild(child2);
  container.appendChild(sp);
  container.appendChild(textEl);
  el.appendChild(container);

  return el;
};

export const removeFullScreenSpinner = () => {
  document.querySelector(".loading-overlay").style.display = "none";
};

export const addOverlaySpinner = (parentId) => {
  const el = document.createElement("div");
  el.classList.add("spotlight-spinner-overlay");
  el.style.display = "none";
  const sp = createSpinner();
  el.appendChild(sp);

  const parentEl = document.getElementById(parentId);
  parentEl.appendChild(el);

  return el;
};

export const showOverlaySpinner = (elId) => {
  const el = document.getElementById(elId);
  const sp = el.querySelector(".spotlight-spinner-overlay");
  sp.style.display = "flex";
};

export const hideOverlaySpinner = (elId) => {
  const el = document.getElementById(elId);
  const sp = el.querySelector(".spotlight-spinner-overlay");
  sp.style.display = "none";
};

const createSpinner = () => {
  const el = document.createElement("div");
  el.classList.add("sk-chase");
  const t = [1, 2, 3, 4, 5, 6];
  t.forEach((_) => {
    const dot = document.createElement("div");
    dot.classList.add("sk-chase-dot");
    el.appendChild(dot);
  });
  return el;
};
