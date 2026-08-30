// Run: bun test tests/quiz.test.ts
//
// quiz.ts imports @earendil-works/pi-tui and @sinclair/typebox at runtime.
// Bun 1.3.5 does not resolve these through NODE_PATH for `bun test` (its
// bundler ignores NODE_PATH even though `bun -e` honors it), so give the
// agent directory its own node_modules with symlinks into the installed
// pi-coding-agent package before running the command above:
//
//   mkdir -p node_modules/@earendil-works node_modules/@sinclair
//   ln -sfn /opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui node_modules/@earendil-works/pi-tui
//   ln -sfn /opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/typebox node_modules/@sinclair/typebox
//
// (node_modules/ is local scaffolding for this run only. It is not
// committed. .chezmoiignore and .gitignore both list
// dot_omp/agent/node_modules, so this scaffold is never deployed by
// `chezmoi apply` and never picked up by `git add`.)
import { describe, expect, test } from "bun:test";
import { coerceCorrectAnswer, isCorrect, normalizeOptions, resolveCorrect, shuffleOptions } from "../extensions/quiz";

const opts = normalizeOptions([
	{ label: "Mercury", value: "mercury" },
	{ label: "Venus", value: "venus" },
	{ label: "Earth" },
]);

describe("quiz grading", () => {
	test("value defaults to the label", () => {
		expect(opts[2].value).toBe("Earth");
	});
	test("resolveCorrect maps values to 1-based display indices", () => {
		expect(resolveCorrect("venus", opts).indices).toEqual([2]);
		expect(resolveCorrect(["mercury", "Earth"], opts).indices).toEqual([1, 3]);
	});
	test("unknown value is a hard error", () => {
		expect(resolveCorrect("pluto", opts).error).toContain("pluto");
	});
	test("multi-select is an exact set match", () => {
		expect(isCorrect([1, 3], [1, 3])).toBe(true);
		expect(isCorrect([1], [1, 3])).toBe(false);
		expect(isCorrect([1, 2, 3], [1, 3])).toBe(false);
	});
	test("a JSON-encoded array string is coerced", () => {
		expect(coerceCorrectAnswer('["a","b"]')).toEqual(["a", "b"]);
	});
	test("shuffle keeps the same set", () => {
		const s = shuffleOptions(opts);
		expect(s.map((o) => o.value).sort()).toEqual(opts.map((o) => o.value).sort());
	});
});
