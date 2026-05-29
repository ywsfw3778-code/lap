function parseReplyMessage(raw){
  const text = String(raw || '').trim();
  if (text.startsWith('[reply:')) {
    const endIdx = text.indexOf('}]');
    if (endIdx !== -1) {
      const jsonStr = text.substring('[reply:'.length, endIdx + 1);
      const actualText = text.substring(endIdx + 2);
      try {
        const replyMeta = JSON.parse(jsonStr);
        return {
          isReply: true,
          replyId: replyMeta.id,
          replySender: replyMeta.sender,
          replyText: replyMeta.text,
          actualText: actualText
        };
      } catch (e) {
        console.warn('Failed to parse reply JSON:', e.message);
      }
    }
  }
  return { isReply: false, replyId: '', replySender: '', replyText: '', actualText: text };
}

const rawText = `[reply:{"id":"2213","sender":"Jinx","text":"تبا للنت"}]معلش يا حياتي ممواههه`;
const result = parseReplyMessage(rawText);
console.log('Result:', result);
