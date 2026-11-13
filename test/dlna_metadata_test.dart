import 'package:flutter_test/flutter_test.dart';
import 'package:dlna_dart/dlna.dart';
import 'package:xml/xml.dart' hide XmlText;
import 'package:dlna_dart/xmlParser.dart';
import 'package:kazumi/services/player/remote.dart';

void main() {
  test('only AVTransport services can be selected', () {
    expect(
        supportsDlnaTransport([
          {'serviceId': 'urn:upnp-org:serviceId:AVTransport'}
        ]),
        true);
    expect(
        supportsDlnaTransport([
          {'serviceId': 'urn:upnp-org:serviceId:AVTransport1'}
        ]),
        true);
    expect(
        supportsDlnaTransport([
          {'serviceId': 'urn:upnp-org:serviceId:ContentDirectory'}
        ]),
        false);
    expect(
        supportsDlnaTransport([
          {'serviceId': 'fakeAVTransport'}
        ]),
        false);
  });
  test('title and URL survive nested SOAP and DIDL escaping', () {
    const title = '番剧 <A> & B · 第一集';
    const url = 'https://example.invalid/movie?a=1&b=2';
    final soap = XmlDocument.parse(XmlText.setPlayURLXml(url,
        title: escapeDlnaTitle(title), type: PlayType.Video));
    expect(soap.findAllElements('CurrentURI').single.innerText, url);
    final didl = XmlDocument.parse(
        soap.findAllElements('CurrentURIMetaData').single.innerText);
    expect(didl.findAllElements('dc:title').single.innerText, title);
  });
}
