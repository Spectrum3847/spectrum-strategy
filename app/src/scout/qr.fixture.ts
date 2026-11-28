import { parseConfig } from "./config";
import type { ScheduledMatch } from "./schedule";

export const qrConfig = parseConfig({
  title: "T",
  revision: 1,
  delimiter: "\t",
  sections: [
    {
      name: "Pre",
      fields: [
        { code: "scouter", type: "text" },
        { code: "matchNumber", type: "TBA-match-number" },
        {
          code: "robot",
          type: "select",
          choices: { R2: "Red 2", B1: "Blue 1" },
        },
        { code: "pTnumber", type: "number" },
      ],
    },
    {
      name: "Match",
      fields: [
        { code: "fuel", type: "counter" },
        { code: "level", type: "range" },
        { code: "defense", type: "boolean" },
        {
          code: "traits",
          type: "checkbox-select",
          choices: { a: "A", b: "B" },
        },
        {
          code: "track",
          type: "action-tracker",
          actions: [
            { code: "a", label: "A" },
            { code: "b", label: "B" },
          ],
        },
        { code: "notes", type: "long-text" },
      ],
    },
  ],
});

export const schedule: ScheduledMatch[] = [
  {
    key: "2027test_qm12",
    compLevel: "qm",
    matchNumber: 12,
    red: [100, 1234, 300],
    blue: [400, 500, 600],
  },
];

export const referencePayload =
  "Sam\t12\tR2\t1234\t7\t3.5\ttrue\ta,b\t2\t1.5-2.5,8\t0\t\tgood auto ok";

export const entryValues = {
  scouter: "Sam",
  matchNumber: "12",
  robot: "R2",
  pTnumber: "1234",
  fuel: 7,
  level: 3.5,
  defense: true,
  traits: "a,b",
  track_a_count: 2,
  track_a_times: "1.5-2.5,8",
  track_b_count: 0,
  track_b_times: "",
  notes: "good\tauto\nok",
};

const phase = '{"score":0,"penalties":0,"notes":"","counters":{}}';

export const referenceSignature =
  '{"matchId":"","tbaMatchKey":"2027test_qm12","teamNumber":1234,' +
  '"alliance":"Red","notes":"","fieldValues":{"defense":true,"fuel":7,' +
  '"level":3.5,"matchNumber":12,"notes":"good auto ok","pTnumber":1234,' +
  '"robot":"R2","scouter":"Sam","track_a_count":2,' +
  '"track_a_times":"1.5-2.5,8","track_b_count":0,"track_b_times":"",' +
  `"traits":"a,b"},"byPhase":{"auton":${phase},"teleop":${phase},"endgame":${phase}}}`;

export const referenceScanId = "scan-be99d2a4";
