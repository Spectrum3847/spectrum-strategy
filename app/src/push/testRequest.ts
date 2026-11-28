export interface TestAnswer {
  ok: boolean;
  text: string;
}

export function describeTestResponse(
  status: number,
  body: unknown,
): TestAnswer {
  const fields =
    body && typeof body === "object" ? (body as Record<string, unknown>) : {};
  if (status === 200 && fields.ok === true) {
    return {
      ok: true,
      text: "Sent. It should show on this device in a few seconds. If it does not, check Focus or Do Not Disturb and this device's notification settings.",
    };
  }
  if (status === 200) {
    return {
      ok: false,
      text:
        fields.gone && Number(fields.gone) > 0
          ? "The push service dropped this device. Turn reminders off and on again."
          : "The push service did not take the test. Try again in a minute.",
    };
  }
  if (status === 404) {
    return {
      ok: false,
      text: "This device is not saved in the database yet. Check the Outbox under Data, then try again.",
    };
  }
  if (status === 401) {
    return {
      ok: false,
      text: "Your sign-in expired. Sign in again, then retry.",
    };
  }
  if (status === 503) {
    return {
      ok: false,
      text: "The server is not set up to send reminders yet. Tell a developer.",
    };
  }
  return {
    ok: false,
    text: `The server could not send the test (status ${status}).`,
  };
}
