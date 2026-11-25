import { spawnSync } from 'node:child_process';
import { closeSync, mkdtempSync, openSync, readFileSync, rmdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const ORIGIN = 'https://chatgpt.com';
const ANCHORS = {
  composer: '[contenteditable="true"][role="textbox"]:visible',
  composerName: '^(询问 ChatGPT|与 ChatGPT 聊天|Ask ChatGPT|Chat with ChatGPT|使用 ChatGPT Work|Use ChatGPT Work)$',
  workComposer: '^(使用 ChatGPT Work|Use ChatGPT Work)$',
  send: '^(发送|发送消息|Send|Send message)$',
  login: '^(登录|Log in)$',
  turnKey: 'data-content-search-turn-key',
  assistant: '[data-conversation-role="assistant"]',
  turnState: 'data-talvt-turn-state',
  response: '[data-response-body]',
  composerMode: '^(撰写器模式|Composer mode)$',
  newChat: '^(新聊天|New chat)$',
  workMode: '^(工作|Work)$',
  modelPicker: '^(选择 ChatGPT 模型|Choose ChatGPT model)$',
  effort: '^(强度|Effort)$',
};

const USAGE = `node chatgpt.mjs <open|probe|ask|work> [--workspace PATH] [--session NAME] [--prompt TEXT]
  open   Open a headed Chrome session with a persistent profile for manual sign-in.
  probe  Report composer visibility and the latest completed assistant reply.
  ask    Send the supplied prompt in the active ChatGPT tab and print its reply.
  work   Open the Work composer and set its reasoning effort to High.
  Default workspace: current directory
  Default session: chatgpt-persistent
  Set CHATGPT_PLAYWRIGHT_WRAPPER to use another installed Playwright wrapper.`;

async function operate(page, { origin, anchors, command, prompt }) {
  if (new URL(page.url()).origin !== origin) throw new Error(`Open ${origin} in the selected Chrome tab.`);
  const findComposer = (name = anchors.composerName) => (
    page.getByRole('textbox', { name: new RegExp(name, 'i') }).and(page.locator(anchors.composer))
  );
  const composer = findComposer();
  const loggedOut = await page.getByRole('button', { name: new RegExp(anchors.login, 'i') }).first().isVisible();

  if (command === 'work') {
    if (loggedOut) throw new Error('Sign in manually in the headed Chrome window, then run work again.');
    if (await composer.count() === 1 && (await composer.innerText()).trim()) throw new Error('The ChatGPT composer already contains a draft.');
    const mode = page.getByRole('group', { name: new RegExp(anchors.composerMode, 'i') });
    if (!await mode.isVisible() && new URL(page.url()).pathname !== '/') {
      const newChat = page.getByRole('button', { name: new RegExp(anchors.newChat, 'i') })
        .and(page.locator('button:visible'));
      if (await newChat.count() === 1) {
        await newChat.click({ timeout: 10_000 });
      } else {
        await page.goto(origin, { waitUntil: 'domcontentloaded' });
      }
    }
    const work = mode.getByRole('button', { name: new RegExp(anchors.workMode, 'i') });
    await work.waitFor({ state: 'visible', timeout: 30_000 });
    if (await work.getAttribute('aria-pressed') !== 'true') await work.click();
    const workComposer = findComposer(anchors.workComposer);
    await workComposer.waitFor({ state: 'visible', timeout: 10_000 });
    const workForm = workComposer.locator('xpath=ancestor::form[1]');
    const pickerName = new RegExp(anchors.modelPicker, 'i');
    await workForm.getByRole('button', { name: pickerName }).click({ timeout: 10_000 });
    const menu = page.getByRole('menu', { name: pickerName });
    const effort = menu.getByRole('menuitem', { name: new RegExp(anchors.effort, 'i') });
    const status = menu.getByRole('status');
    const levels = [/^(无|None|Off)$/i, /^(极低|Minimal)$/i, /^(轻度|Low|Light)$/i, /^(中|Medium)$/i, /^(高|High)$/i, /^(极高|XHigh|Extra High)$/i, /^(Max|Ultra|持续)$/i];
    try {
      await effort.waitFor({ state: 'visible', timeout: 10_000 });
      for (let step = 0; step < levels.length; step++) {
        const label = (await status.innerText()).split(/[,，]/, 1)[0].trim();
        const current = levels.findIndex(pattern => pattern.test(label));
        if (current === 4) return { url: page.url(), mode: 'Work', reasoningEffort: 'high' };
        if (current === -1) throw new Error(`Unrecognized Work reasoning effort: ${label}`);
        await effort.press(current < 4 ? 'ArrowRight' : 'ArrowLeft');
      }
      throw new Error('High reasoning effort could not be verified.');
    } finally {
      await page.keyboard.press('Escape');
    }
  }

  const replies = page.locator(`[${anchors.turnKey}]:has(${anchors.assistant})`);
  const previousKeys = await replies.evaluateAll((turns, key) => turns.map(turn => turn.getAttribute(key)), anchors.turnKey);
  const completedBody = `[${anchors.turnState}="complete"] ${anchors.response}`;
  if (prompt === null) {
    const latest = replies.last().locator(completedBody).last();
    return { url: page.url(), composerVisible: await composer.count() === 1, loginButtonVisible: loggedOut, reply: await latest.isVisible() ? (await latest.innerText()).trim() : null };
  }
  if (loggedOut) throw new Error('Sign in manually in the headed Chrome window, then run ask again.');
  await composer.waitFor({ state: 'visible', timeout: 10_000 });
  if (await page.locator(`[${anchors.turnState}]:not([${anchors.turnState}="complete"]):visible`).count()) throw new Error('Wait for the current ChatGPT reply to finish.');
  const draft = (await composer.innerText()).trim();
  if (draft && draft !== prompt.trim()) throw new Error('The ChatGPT composer already contains a different draft.');
  if (!draft) await composer.fill(prompt);
  const form = composer.locator('xpath=ancestor::form[1]');
  await form.getByRole('button', { name: new RegExp(anchors.send, 'i') }).click({ timeout: 10_000 });
  const freshReply = page.locator(`[${anchors.turnKey}]${previousKeys.map(key => `:not([${anchors.turnKey}=${JSON.stringify(key)}])`).join('')}:has(${anchors.assistant})`).last().locator(completedBody).last();
  try {
    await freshReply.waitFor({ state: 'visible', timeout: 90_000 });
  } catch (error) {
    throw new Error('Prompt was submitted but no completed reply was detected. Check the Chrome tab before retrying.', { cause: error });
  }
  return { url: page.url(), reply: (await freshReply.innerText()).trim() };
}

function runWrapper(workspace, args, outputFile) {
  const wrapper = process.env.CHATGPT_PLAYWRIGHT_WRAPPER ?? fileURLToPath(
    new URL('./playwright-automation.ps1', import.meta.url),
  );
  const fd = outputFile ? openSync(outputFile, 'w') : undefined;
  let result;
  try {
    result = spawnSync('powershell.exe', ['-NoProfile', '-File', wrapper, ...args], { cwd: workspace, encoding: 'utf8', windowsHide: true, stdio: fd === undefined ? 'pipe' : ['ignore', fd, fd] });
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
  if (result.error) throw result.error;
  const stdout = (outputFile ? readFileSync(outputFile, 'utf8') : result.stdout).trim();
  if (result.status !== 0 || /^### Error\b/m.test(stdout)) throw new Error([stdout.split('\n### Ran Playwright code')[0], result.stderr?.trim()].filter(Boolean).join('\n'));
  return stdout;
}

function main() {
  const { positionals: [command, ...extra], values } = parseArgs({ allowPositionals: true, options: { help: { type: 'boolean' }, session: { type: 'string' }, prompt: { type: 'string' }, workspace: { type: 'string' } } });
  if (values.help) return console.log(USAGE);
  if (extra.length || !['open', 'probe', 'ask', 'work'].includes(command) || (command === 'ask' ? !values.prompt?.trim() : values.prompt !== undefined)) throw new Error(USAGE);
  const workspace = resolve(values.workspace ?? process.cwd());
  const session = values.session ?? 'chatgpt-persistent';
  if (!/^[a-z0-9][a-z0-9._-]*$/i.test(session)) throw new Error('Invalid session name.');
  const sessionArgs = ['--session', session];
  const sessions = runWrapper(workspace, ['sessions']);
  const sessionOpen = sessions.split(/\r?\n/).some((line, index, lines) => line === `- ${session}:` && lines[index + 1]?.trim() === '- status: open');
  if (command === 'open') {
    if (sessionOpen) return console.log(`Chrome session ${session} is already open in workspace ${workspace}.`);
    const openDir = mkdtempSync(join(workspace, 'output', 'playwright', `${session}-open-`));
    const outputFile = join(openDir, 'open.log');
    try {
      return console.log(runWrapper(workspace, ['open', ORIGIN, ...sessionArgs, '--mode', 'headed', '--browser', 'chrome', '--persistent'], outputFile));
    } finally {
      rmSync(outputFile, { force: true });
      rmdirSync(openDir);
    }
  }
  if (!sessionOpen) {
    throw new Error(`Chrome session ${session} is not open in workspace ${workspace}. Run open with the same --workspace and --session.`);
  }
  const artifactDir = mkdtempSync(join(workspace, 'output', 'playwright', `${session}-call-`));
  try {
    const filename = join(artifactDir, 'operation.js');
    writeFileSync(filename, `async page => (${operate})(page, ${JSON.stringify({ origin: ORIGIN, anchors: ANCHORS, command, prompt: values.prompt ?? null })})`, 'utf8');
    const output = runWrapper(workspace, ['run', 'run-code', '--filename', filename, ...sessionArgs]);
    const result = output.match(/^### Result\r?\n([\s\S]*?)(?=\r?\n### |$)/m);
    if (!result) throw new Error('Playwright returned no ChatGPT result.');
    console.log(JSON.stringify({ workspace, ...JSON.parse(result[1]) }, null, 2));
  } finally {
    rmSync(join(artifactDir, 'operation.js'), { force: true });
    rmdirSync(artifactDir);
  }
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
