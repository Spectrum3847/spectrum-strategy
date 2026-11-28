// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DeleteButton } from "./DeleteButton";

afterEach(cleanup);

const show = (onConfirm = vi.fn(() => Promise.resolve())) => {
  render(
    <DeleteButton
      what="team 1111, Q5"
      prompt="Delete it?"
      onConfirm={onConfirm}
    />,
  );
  return onConfirm;
};

describe("DeleteButton", () => {
  it("deletes nothing until the prompt is confirmed", async () => {
    const onConfirm = show();
    fireEvent.click(
      screen.getByRole("button", { name: "Delete team 1111, Q5" }),
    );
    expect(screen.getByText("Delete it?")).toBeTruthy();
    expect(onConfirm).not.toHaveBeenCalled();
    fireEvent.click(
      screen.getByRole("button", { name: "Confirm delete team 1111, Q5" }),
    );
    await waitFor(() => expect(onConfirm).toHaveBeenCalledTimes(1));
  });

  it("backs out with Cancel and with Escape", () => {
    const onConfirm = show();
    fireEvent.click(screen.getByRole("button", { name: /^Delete team/ }));
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(screen.queryByText("Delete it?")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: /^Delete team/ }));
    fireEvent.keyDown(screen.getByRole("group"), { key: "Escape" });
    expect(screen.queryByText("Delete it?")).toBeNull();
    expect(onConfirm).not.toHaveBeenCalled();
  });

  it("says so when the delete fails", async () => {
    show(vi.fn(() => Promise.reject(new Error("Training mode."))));
    fireEvent.click(screen.getByRole("button", { name: /^Delete team/ }));
    fireEvent.click(screen.getByRole("button", { name: /^Confirm delete/ }));
    expect((await screen.findByRole("alert")).textContent).toBe(
      "Training mode.",
    );
  });
});
