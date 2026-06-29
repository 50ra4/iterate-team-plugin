#!/usr/bin/env node
// iterate-team-plugin 登録ヘルパ CLI。
//
// 本パッケージの実体は Claude Code プラグイン。${CLAUDE_PLUGIN_ROOT} の解決は
// Claude Code のプラグインローダに委ねるため、本 CLI は資産を対象リポへコピーせず、
// (1) agent 定義の再生成（build）と (2) プラグイン登録手順の案内（install / 既定）
// のみを担う。
//
// 使い方:
//   npx iterate-team-plugin            # 登録手順を表示（既定）
//   npx iterate-team-plugin install    # 同上
//   npx iterate-team-plugin build      # templates/ から agents/ を再生成
//   npx iterate-team-plugin path       # プラグインルートの絶対パスを表示

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const pluginRoot = dirname(dirname(fileURLToPath(import.meta.url)));

function build() {
  const script = join(pluginRoot, 'scripts', 'build-agents.sh');
  const res = spawnSync('bash', [script], { stdio: 'inherit' });
  if (res.error) {
    console.error(`build-agents 実行に失敗しました: ${res.error.message}`);
    return 1;
  }
  return res.status ?? 0;
}

function printInstall() {
  console.log(`iterate-team plugin

プラグインルート:
  ${pluginRoot}

Claude Code への登録（ローカルマーケットプレイス経由）:
  1) /plugin marketplace add ${pluginRoot}
  2) /plugin install iterate-team@iterate-team

登録後:
  - SessionStart hook が対象リポジトリ直下に .iterate-team/{state,tasks,changes}/ を seed します
  - /iterate-team <要望文>            計画→並列実装→検収→PR を一括実行
  - /iterate-plan / /iterate-build / /iterate-review  フェーズ分割実行

agent 定義を再生成する場合:
  npx iterate-team-plugin build
`);
  return 0;
}

const cmd = process.argv[2] ?? 'install';
let code = 0;
switch (cmd) {
  case 'build':
    code = build();
    break;
  case 'path':
    console.log(pluginRoot);
    break;
  case 'install':
  case undefined:
    code = printInstall();
    break;
  default:
    console.error(`unknown command: ${cmd}`);
    console.error('usage: iterate-team-plugin [install|build|path]');
    code = 2;
}
process.exit(code);
