// implement some polish logic here
$(document).on("shiny:connected", function () {
  console.log("processing virtual select widget");
  // append additional class to virtual select widgets
  const buttons = document.querySelectorAll(".vscomp-toggle-button");
  console.log("buttons", buttons);
  document
    .querySelectorAll(".vscomp-ele")
    .forEach((e) => e.classList.add("border", "rounded-2"));
  document
    .querySelectorAll(".vscomp-ele-wrapper")
    .forEach((e) => e.classList.add("border", "rounded-2", "focus-ring"));
  document
    .querySelectorAll(".vscomp-toggle-button")
    .forEach((e) => e.classList.add("border", "rounded-2"));
});
