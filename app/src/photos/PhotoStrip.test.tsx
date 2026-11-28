// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { net, photoQueue, resetQueue } from "./fakeService";
import { PhotoGallery } from "./PhotoGallery";
import { PhotoStrip } from "./PhotoStrip";
import { slotKeys, waitingText } from "./state";
import { type EntryPhotos, useEntryPhotos } from "./useEntryPhotos";

const stored = vi.hoisted(() => ({ value: true }));
vi.mock("../outbox/settled", () => ({
  whenInDatabase: () => Promise.resolve(stored.value),
}));
vi.mock("./service", () => import("./fakeService"));
vi.mock("./compress", () => ({
  preparePhoto: vi.fn(async (file: File) => file),
}));

const noKeys: string[] = [];
const oneKey = ["old-1.jpg"];
const threeKeys = ["a.jpg", "b.jpg", "c.jpg"];

let latest: EntryPhotos | null = null;

function Harness({
  keys,
  entryId = "e1",
}: {
  keys: string[];
  entryId?: string | null;
}) {
  const photos = useEntryPhotos(
    { entryId, team: 1111, eventKey: "2027test" },
    keys,
  );
  latest = photos;
  return (
    <>
      <PhotoStrip photos={photos} />
      <output aria-label="keys">{slotKeys(photos.slots).join(",")}</output>
    </>
  );
}

const file = () => new File(["x"], "robot.jpg", { type: "image/jpeg" });

function pick(container: HTMLElement, selector = "input[multiple]") {
  const input = container.querySelector(selector) as HTMLInputElement;
  fireEvent.change(input, { target: { files: [file()] } });
}

beforeEach(async () => {
  latest = null;
  await resetQueue();
  URL.createObjectURL = vi.fn(() => "blob:local");
  URL.revokeObjectURL = vi.fn();
});
afterEach(cleanup);

describe("photo strip", () => {
  it("shows the photos already on the entry, loaded from the Worker", async () => {
    render(<Harness keys={oneKey} />);
    const thumb = await screen.findByRole("button", { name: "View photo 1" });
    expect(thumb.querySelector("img")?.getAttribute("src")).toBe(
      "blob:old-1.jpg",
    );
    expect(net.fetchPhoto).toHaveBeenCalledWith("old-1.jpg");
    expect(screen.getByText("Uploaded")).toBeTruthy();
  });

  it("says why a photo cannot be shown and tries again on request", async () => {
    net.fetchPhoto.mockResolvedValueOnce({
      type: "unavailable",
      reason: "offline",
    });
    render(<Harness keys={oneKey} />);
    await screen.findByText("Connect to see this photo");
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    await screen.findByRole("button", { name: "View photo 1" });
    expect(net.fetchPhoto).toHaveBeenCalledTimes(2);
  });

  it("uploads a picked photo and shows its key", async () => {
    const { container } = render(<Harness keys={noKeys} />);
    pick(container);
    await screen.findByText("Uploaded");
    expect(screen.getByLabelText("keys").textContent).toBe("new-key.jpg");
    expect(net.upload).toHaveBeenCalledTimes(1);
  });

  it("asks for a camera on the camera input", () => {
    const { container } = render(<Harness keys={noKeys} />);
    const camera = container.querySelector("input[capture]");
    expect(camera?.getAttribute("accept")).toBe("image/*");
    expect(camera?.getAttribute("capture")).toBe("environment");
  });

  it("shows a photo picked offline as waiting, with no key yet", async () => {
    net.upload.mockResolvedValue({ type: "unavailable", reason: "offline" });
    const { container } = render(<Harness keys={noKeys} />);
    pick(container, "input[capture]");
    await screen.findByText("Waiting for a connection");
    expect(screen.getByLabelText("keys").textContent).toBe("");
    expect(screen.getByRole("button", { name: "View photo 1" })).toBeTruthy();
  });

  it("offers a retry for a photo the server refused", async () => {
    net.upload.mockResolvedValue({ type: "response", status: 413 });
    const { container } = render(<Harness keys={noKeys} />);
    pick(container);
    await screen.findByText(/Too large for the photo server/);
    net.upload.mockResolvedValue({
      type: "response",
      status: 201,
      key: "second.jpg",
    });
    fireEvent.click(screen.getByRole("button", { name: "Retry upload" }));
    await screen.findByText("Uploaded");
    expect(screen.getByLabelText("keys").textContent).toBe("second.jpg");
  });

  it("stops adding at three photos", () => {
    render(<Harness keys={threeKeys} />);
    expect(
      (screen.getByRole("button", { name: "Take photo" }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);
    expect(
      (
        screen.getByRole("button", {
          name: "Choose photo",
        }) as HTMLButtonElement
      ).disabled,
    ).toBe(true);
  });

  it("does not add past three when several are picked at once", async () => {
    const { container } = render(<Harness keys={["a.jpg", "b.jpg"]} />);
    const input = container.querySelector(
      "input[multiple]",
    ) as HTMLInputElement;
    fireEvent.change(input, { target: { files: [file(), file()] } });
    await screen.findByText(/Only 3 photos fit, 1 not added/);
    expect(net.upload).toHaveBeenCalledTimes(1);
  });

  it("reports a photo it cannot read", async () => {
    const { preparePhoto } = await import("./compress");
    vi.mocked(preparePhoto).mockRejectedValueOnce(new Error("bad"));
    const { container } = render(<Harness keys={noKeys} />);
    pick(container);
    await screen.findByText(/could not be read or is too large/);
    expect(net.upload).not.toHaveBeenCalled();
  });

  it("asks before removing, and keeps the photo on Keep", async () => {
    render(<Harness keys={oneKey} />);
    await screen.findByRole("button", { name: "View photo 1" });
    fireEvent.click(screen.getByRole("button", { name: "Remove photo 1" }));
    const group = screen.getByRole("group", { name: "Remove photo 1" });
    expect(within(group).getByText("Remove this photo?")).toBeTruthy();
    fireEvent.click(within(group).getByRole("button", { name: "Keep" }));
    expect(screen.getByLabelText("keys").textContent).toBe("old-1.jpg");
    expect(net.remove).not.toHaveBeenCalled();
  });

  async function removeFirst() {
    await screen.findByRole("button", { name: "View photo 1" });
    fireEvent.click(screen.getByRole("button", { name: "Remove photo 1" }));
    fireEvent.click(
      within(screen.getByRole("group", { name: "Remove photo 1" })).getByRole(
        "button",
        { name: "Remove" },
      ),
    );
  }

  it("takes a saved photo off the entry now and out of the bucket once stored", async () => {
    render(<Harness keys={oneKey} />);
    await removeFirst();
    expect(screen.getByLabelText("keys").textContent).toBe("");
    expect(net.detach).toHaveBeenCalledWith("e1", "old-1.jpg");
    await waitFor(() => expect(net.remove).toHaveBeenCalledWith("old-1.jpg"));
  });

  it("keeps a removed photo in the bucket when the removal is not stored", async () => {
    stored.value = false;
    render(<Harness keys={oneKey} />);
    await removeFirst();
    await new Promise((r) => setTimeout(r, 0));
    expect(net.detach).toHaveBeenCalledTimes(1);
    expect(net.remove).not.toHaveBeenCalled();
    stored.value = true;
  });

  it("deletes the object at once when the entry no longer holds the photo", async () => {
    net.detach.mockResolvedValue("absent");
    render(<Harness keys={oneKey} />);
    await removeFirst();
    await waitFor(() => expect(net.remove).toHaveBeenCalledWith("old-1.jpg"));
  });

  it("brings the photo back and says so when the entry cannot be reached", async () => {
    net.detach.mockResolvedValue("no-entry");
    render(<Harness keys={oneKey} />);
    await removeFirst();
    await screen.findByText(/Could not remove the photo/);
    expect(screen.getByLabelText("keys").textContent).toBe("old-1.jpg");
    expect(net.remove).not.toHaveBeenCalled();
  });

  it("removes a photo no entry holds at once, object included", async () => {
    const { container } = render(<Harness keys={noKeys} />);
    pick(container);
    await screen.findByText("Uploaded");
    fireEvent.click(screen.getByRole("button", { name: "Remove photo 1" }));
    fireEvent.click(
      within(screen.getByRole("group", { name: "Remove photo 1" })).getByRole(
        "button",
        { name: "Remove" },
      ),
    );
    await waitFor(() => expect(net.remove).toHaveBeenCalledWith("new-key.jpg"));
    expect(screen.queryByRole("button", { name: "View photo 1" })).toBeNull();
    expect(latest?.slots).toEqual([]);
  });

  it("holds a photo for a team with no entry and says why", async () => {
    const { container } = render(<Harness keys={noKeys} entryId={null} />);
    pick(container);
    await screen.findByText("Uploaded");
    expect(screen.getByText(waitingText)).toBeTruthy();
    expect(net.upload).toHaveBeenCalledTimes(1);
    expect(net.attach).not.toHaveBeenCalled();
  });

  it("attaches a waiting photo once the entry is known", async () => {
    const { container } = render(<Harness keys={noKeys} entryId={null} />);
    pick(container);
    await screen.findByText("Uploaded");
    const [waiting] = photoQueue.items();
    photoQueue.place(new Map([[waiting?.id ?? "", "e9"]]));
    await waitFor(() =>
      expect(net.attach).toHaveBeenCalledWith("e9", ["new-key.jpg"]),
    );
  });

  it("opens a larger view and closes it", async () => {
    render(<Harness keys={oneKey} />);
    fireEvent.click(
      await screen.findByRole("button", { name: "View photo 1" }),
    );
    const dialog = screen.getByRole("dialog", { name: "photo 1" });
    expect(dialog.querySelector("img")?.getAttribute("src")).toBe(
      "blob:old-1.jpg",
    );
    fireEvent.click(within(dialog).getByRole("button", { name: "Close" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  });
});

describe("photo gallery", () => {
  it("renders nothing for an entry with no photos", () => {
    const { container } = render(<PhotoGallery keys={[]} />);
    expect(container.textContent).toBe("");
  });

  it("shows read-only thumbnails that open a larger view", async () => {
    render(<PhotoGallery keys={["a.jpg", "b.jpg"]} />);
    const thumbs = await screen.findAllByRole("button", { name: /View photo/ });
    expect(thumbs).toHaveLength(2);
    expect(screen.queryByRole("button", { name: /Remove/ })).toBeNull();
    fireEvent.click(thumbs[1] as HTMLElement);
    expect(screen.getByRole("dialog", { name: "photo 2" })).toBeTruthy();
  });

  it("explains a photo that is not set up or not allowed", async () => {
    net.fetchPhoto.mockResolvedValue({
      type: "unavailable",
      reason: "unconfigured",
    });
    render(<PhotoGallery keys={["a.jpg"]} />);
    await screen.findByText("Photo storage is not set up");
  });
});
