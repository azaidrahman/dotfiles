// Byte format of the lesson note that lesson-log.ts appends to. The Claude
// Code hook (dot_claude/hooks/executable_lesson-log.sh) writes the same
// format. dot_claude/tests/fixtures/lesson-log/expected.md is the reference.

export function callout(type: string, title: string, body: string[]): string {
	const lines = [`> [!${type}] ${title}`];
	for (const line of body) lines.push(line.length === 0 ? ">" : `> ${line}`);
	return lines.join("\n");
}

export function youBlock(text: string): string {
	return callout("quote", "YOU", text.split("\n"));
}

export function tutorBlock(text: string): string {
	return callout("abstract", "TUTOR", text.split("\n"));
}

export function questionBlock(question: string, labels: string[]): string {
	const body = question.split("\n");
	if (labels.length > 0) {
		body.push("");
		labels.forEach((l, i) => body.push(`${i + 1}. ${l}`));
	}
	return callout("question", "Question", body);
}

// omp's `ask` tool returns one line per question. Two shapes exist in the
// binary: "User selected: a, b" / "User provided custom input: x" /
// "User added note: x", and the compact "<id>: a", "<id>: [a, b]", '<id>: "x"'.
export function askAnswerLines(resultText: string): string[] {
	const out: string[] = [];
	for (const raw of resultText.split("\n")) {
		const line = raw.trim();
		if (!line) continue;
		let m: RegExpMatchArray | null;
		if ((m = line.match(/^User selected: (.*)$/))) out.push(m[1]);
		else if ((m = line.match(/^User provided custom input: (.*)$/))) out.push(m[1]);
		else if ((m = line.match(/^User added note: (.*)$/))) out.push(m[1]);
		else if (/^User (cancelled|did not select)/.test(line)) out.push("(no answer)");
		else if ((m = line.match(/^[\w-]+: \[(.*)\]$/))) out.push(m[1]);
		else if ((m = line.match(/^[\w-]+: "(.*)"$/))) out.push(m[1]);
		else if ((m = line.match(/^[\w-]+: (.*)$/))) out.push(m[1].replace(/ \((cancelled|auto-selected after timeout)\)$/, ""));
	}
	return out.length ? out : ["(no answer)"];
}

export interface QuizGrade {
	correct: boolean;
	dontKnow: boolean;
	correctLabels: string[];
	explanation: string;
}

export function quizGradeBlock(g: QuizGrade): string {
	const answer = g.correctLabels.join(", ");
	const first = g.dontKnow
		? `The answer is ${answer}.`
		: g.correct
			? "Correct."
			: `Not correct. The answer is ${answer}.`;
	const body = [first];
	if (g.explanation.trim()) body.push("", ...g.explanation.trim().split("\n"));
	return callout("abstract", "TUTOR", body);
}

// Skill declarations are injected by the host, not typed by the learner.
export function stripSkillBlocks(text: string): string {
	return text.replace(/<skill\b([^>]*)>[\s\S]*?<\/skill>/g, (_m, attrs: string) => {
		const name = /name="([^"]+)"/.exec(attrs)?.[1] ?? "unknown";
		return `[skill loaded: ${name}]`;
	});
}

export function joinBlocks(blocks: string[]): string {
	return blocks.join("\n\n") + "\n";
}
