// React Native UI that runs INSIDE the ExtensionKit extension (separate process). Every result is also
// reported to the host shell over XPC (SpikeBridge.hostCall), so the host's log survives an extension crash.
import React, { useEffect, useState } from 'react';
import { AppRegistry, Button, Keyboard, NativeModules, ScrollView, Text, TextInput, View } from 'react-native';
import { WebView } from 'react-native-webview';

const { SpikeBridge } = NativeModules;
const report = (s) => SpikeBridge.hostCall('report', s);
const mb = (n) => Math.round(n / 1048576);

const html = `<html><head><meta name="viewport" content="width=device-width"></head><body style="font-size:18px">
<input id="i" placeholder="web input" style="font-size:18px;width:90%"/>
<p>WEBVIEW JS OK</p>
<script>
  document.getElementById('i').addEventListener('input', e => window.ReactNativeWebView.postMessage('typed ' + e.target.value));
  window.ReactNativeWebView.postMessage('loaded');
</script></body></html>`;

function App() {
  const [count, setCount] = useState(0);
  const [typed, setTyped] = useState('');
  const [kb, setKb] = useState('none');
  const [web, setWeb] = useState('pending');
  const [mem, setMem] = useState('');
  useEffect(() => {
    report('rn-mounted');
    const a = Keyboard.addListener('keyboardDidShow', (e) => { const h = Math.round(e.endCoordinates.height); setKb('shown ' + h); report('kb-shown ' + h); });
    const b = Keyboard.addListener('keyboardDidHide', () => { setKb('hidden'); report('kb-hidden'); });
    SpikeBridge.memory().then((m) => { const s = `avail ${mb(m.available)}MB footprint ${mb(m.footprint)}MB`; setMem(s); report('mem-start ' + s); });
    return () => { a.remove(); b.remove(); };
  }, []);
  const stress = async () => {
    const keep = [];
    for (let n = 50; n <= 2000; n += 50) {
      keep.push(new Uint8Array(50 * 1048576).fill(n % 255));
      const m = await SpikeBridge.memory();
      report(`alloc ${n}MB avail ${mb(m.available)}MB footprint ${mb(m.footprint)}MB`);
    }
    report('alloc done ' + keep.length);
  };
  return (
    <ScrollView style={{ flex: 1, backgroundColor: '#eef' }} contentContainerStyle={{ padding: 16, paddingTop: 60 }} keyboardShouldPersistTaps="handled">
      <Text testID="rn-title" style={{ fontSize: 20, fontWeight: 'bold' }}>REACT NATIVE IN EXTENSION</Text>
      <Text testID="rn-count" style={{ fontSize: 18 }}>count {count}</Text>
      <Button testID="rn-inc" title="Increment" onPress={() => { setCount((c) => c + 1); report('count ' + (count + 1)); }} />
      <TextInput testID="rn-input" placeholder="type here" onChangeText={(t) => { setTyped(t); report('typed ' + t); }}
        style={{ height: 44, borderWidth: 1, borderColor: '#88a', backgroundColor: 'white', fontSize: 18, paddingHorizontal: 8, marginVertical: 8 }} />
      <Text testID="rn-typed">typed: {typed}</Text>
      <Text testID="rn-kb">keyboard: {kb}</Text>
      <Text>{mem}</Text>
      <View style={{ height: 140, marginVertical: 8, borderWidth: 1 }}>
        <WebView testID="rn-web" originWhitelist={['*']} source={{ html }} onMessage={(e) => { setWeb(e.nativeEvent.data); report('web ' + e.nativeEvent.data); }} />
      </View>
      <Text testID="rn-web-status">web: {web}</Text>
      <Button testID="rn-secure" title="New session (secure)" onPress={() => SpikeBridge.hostCall('secure', JSON.stringify({ store: 'gmail', harness: 'claude' }))} />
      <Button testID="rn-auth" title="Open auth sheet" onPress={() => SpikeBridge.openAuthSession()} />
      <Button testID="rn-mem" title="Memory stress" onPress={stress} />
    </ScrollView>
  );
}

AppRegistry.registerComponent('SpikeApp', () => App);
