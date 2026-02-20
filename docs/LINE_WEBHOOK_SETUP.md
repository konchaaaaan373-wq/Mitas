# LINE Webhook -> Google Drive(CSV) 保存セットアップ

## 1. Netlify側の環境変数を設定
Netlify Site Settings -> Environment variables で以下を追加。

- `LINE_CHANNEL_SECRET`: LINE Messaging API の Channel secret
- `GAS_WEBHOOK_URL`: 後述の Apps Script Web App URL
- `GAS_WEBHOOK_SECRET`: 任意の共有シークレット文字列

## 2. LINE Developers で Webhook URL を設定
LINE Official Account Manager / Developers Console で Webhook URL を以下に設定。

`https://<your-domain>/api/line/webhook`

## 3. Google Apps Script を作成
Google Drive 上で「Googleスプレッドシート」を1つ作成し、Apps Scriptを開いて以下を保存。

```javascript
const SHEET_NAME = 'line_events';
const WEBHOOK_SECRET = 'SET_THE_SAME_VALUE_AS_GAS_WEBHOOK_SECRET';

function doPost(e) {
  try {
    const body = JSON.parse(e.postData.contents || '{}');
    const records = body.records || [];

    if (WEBHOOK_SECRET && body.secret !== WEBHOOK_SECRET) {
      return ContentService.createTextOutput(JSON.stringify({ ok: false, error: 'unauthorized' }))
        .setMimeType(ContentService.MimeType.JSON);
    }

    const ss = SpreadsheetApp.getActiveSpreadsheet();
    let sheet = ss.getSheetByName(SHEET_NAME);
    if (!sheet) {
      sheet = ss.insertSheet(SHEET_NAME);
      sheet.appendRow([
        'receivedAt', 'destination', 'webhookEventId', 'eventType', 'timestamp', 'mode',
        'sourceType', 'sourceUserId', 'sourceGroupId', 'sourceRoomId',
        'messageType', 'messageText', 'rawEvent'
      ]);
    }

    const values = records.map((r) => [
      r.receivedAt || '',
      r.destination || '',
      r.webhookEventId || '',
      r.eventType || '',
      r.timestamp || '',
      r.mode || '',
      r.sourceType || '',
      r.sourceUserId || '',
      r.sourceGroupId || '',
      r.sourceRoomId || '',
      r.messageType || '',
      r.messageText || '',
      r.rawEvent || ''
    ]);

    if (values.length > 0) {
      sheet.getRange(sheet.getLastRow() + 1, 1, values.length, values[0].length).setValues(values);
    }

    return ContentService.createTextOutput(JSON.stringify({ ok: true, inserted: values.length }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({ ok: false, error: String(err) }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}
```

## 4. Apps Script をWebアプリとしてデプロイ
- 実行ユーザー: 自分
- アクセス権: 全員

発行されたURLを `GAS_WEBHOOK_URL` に設定。

## 5. CSV化
以下のいずれかでCSV化可能。

- 手動: スプレッドシート -> ファイル -> ダウンロード -> CSV
- 自動: Apps Script の時間トリガーでCSVを書き出し、Driveに保存

## 補足
- `neco.oncall@gmail.com` のGoogleアカウントで作成したDrive/Sheetsに保存可能です。
- 取得データはWebhookイベントの範囲内です（ユーザーが送ったテキスト、source情報等）。
