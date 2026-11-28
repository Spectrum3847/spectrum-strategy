// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { afterEach, expect, it } from "vitest";
import { Simulations } from "./Simulations";

afterEach(() => {
  cleanup();
  localStorage.clear();
});
it("keeps focus and marks unknown teams while typing", () => {
  render(
    <MemoryRouter>
      <Simulations
        eventKey="test"
        ranking={[1111, 2222]}
        official={[]}
        rounds={2}
        us={1111}
        layout={null}
        robots={new Map()}
      />
    </MemoryRouter>,
  );
  const input = screen.getByLabelText("Alliance 1 Captain");
  input.focus();
  fireEvent.change(input, { target: { value: "9999" } });
  expect(document.activeElement).toBe(input);
  expect(input.getAttribute("aria-invalid")).toBe("true");
  fireEvent.change(input, { target: { value: "1111" } });
  expect(document.activeElement).toBe(input);
  expect(input.getAttribute("aria-invalid")).toBe("false");
});
