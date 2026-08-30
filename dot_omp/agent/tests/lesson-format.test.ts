import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
	askAnswerLines,
	joinBlocks,
	questionBlock,
	quizGradeBlock,
	stripSkillBlocks,
	tutorBlock,
	youBlock,
} from "../lib/lesson-format";

const fixture = readFileSync(
	join(import.meta.dir, "../../../dot_claude/tests/fixtures/lesson-log/expected.md"),
	"utf-8",
);
// Body after the frontmatter: drop everything up to and including the second "---\n".
const body = fixture.split("---\n").slice(2).join("---\n").replace(/^\n/, "");

describe("lesson-format", () => {
	test("reproduces the Claude fixture byte for byte", () => {
		const blocks = [
			youBlock("teach me flannel"),
			tutorBlock("Let us start. A pod on node A sends a packet to a pod on node B."),
			questionBlock("What does the packet hit first after the veth?", ["cni0 bridge", "flannel.1", "I don't know"]),
			youBlock("cni0 bridge"),
			tutorBlock("Correct. The bridge is the first hop.\n\n```mermaid\ngraph TD\n  A[packet] --> B[cni0]\n```"),
			youBlock("What about multi-homing?"),
			questionBlock("Does flannel support VXLAN?", ["Yes", "No"]),
			questionBlock("Does flannel support host-gw?", ["Yes", "No"]),
			youBlock(askAnswerLines("User selected: Yes\nUser selected: No").join("\n")),
			youBlock("check this"),
			questionBlock("Which topics apply?", ["label a", "label b", "label c"]),
			youBlock(askAnswerLines("User selected: label a, label b").join("\n")),
		];
		expect(joinBlocks(blocks)).toBe(body);
	});

	test("askAnswerLines handles the compact id form and custom input", () => {
		expect(askAnswerLines('goal: "make it fast"')).toEqual(["make it fast"]);
		expect(askAnswerLines("goal: [a, b]")).toEqual(["a, b"]);
		expect(askAnswerLines("goal: Yes")).toEqual(["Yes"]);
		expect(askAnswerLines("User provided custom input: hello")).toEqual(["hello"]);
		expect(askAnswerLines("User cancelled the selection")).toEqual(["(no answer)"]);
	});

	test("quizGradeBlock", () => {
		expect(quizGradeBlock({ correct: true, dontKnow: false, correctLabels: ["cni0 bridge"], explanation: "The bridge is the first hop." }))
			.toBe("> [!abstract] TUTOR\n> Correct.\n>\n> The bridge is the first hop.");
		expect(quizGradeBlock({ correct: false, dontKnow: false, correctLabels: ["cni0 bridge"], explanation: "Why." }))
			.toBe("> [!abstract] TUTOR\n> Not correct. The answer is cni0 bridge.\n>\n> Why.");
		expect(quizGradeBlock({ correct: false, dontKnow: true, correctLabels: ["a", "b"], explanation: "Why." }))
			.toBe("> [!abstract] TUTOR\n> The answer is a, b.\n>\n> Why.");
	});

	test("stripSkillBlocks replaces injected skills", () => {
		expect(stripSkillBlocks('hi <skill name="teach">body</skill> there')).toBe("hi [skill loaded: teach] there");
	});

	test("no em dash is ever emitted", () => {
		expect(joinBlocks([youBlock("a"), tutorBlock("b")])).not.toContain("—");
	});
});
