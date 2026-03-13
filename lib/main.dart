import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════
// THEME
// ═══════════════════════════════════════════════════════════
const kBg      = Color(0xFF0A0E1A);
const kSurface = Color(0xFF111827);
const kCard    = Color(0xFF1A2235);
const kAccent  = Color(0xFF1E6FFF);
const kALight  = Color(0xFF4D9FFF);
const kGreen   = Color(0xFF00E5A0);
const kRed     = Color(0xFFFF4D6D);
const kYellow  = Color(0xFFFFD60A);
const kText    = Color(0xFFE8EEF8);
const kDim     = Color(0xFF8B9AB2);
const kBorder  = Color(0xFF1E3055);

// ═══════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════
class NmeaData {
  double? latitude, longitude, sog, cog, altitude;
  String? utcTime, gpsStatus;
  int?    satellites;
  double? awa, aws, twa, tws, twd;
  double? stw, heading;
  double? heel, pitch, pressure, airTemp, waterTemp;
  double? vmg;
  DateTime updated = DateTime.now();

  NmeaData();

  NmeaData copy() {
    final n = NmeaData();
    n.latitude   = latitude;   n.longitude = longitude; n.sog = sog;
    n.cog        = cog;        n.altitude  = altitude;
    n.utcTime    = utcTime;    n.gpsStatus = gpsStatus;
    n.satellites = satellites;
    n.awa = awa; n.aws = aws; n.twa = twa; n.tws = tws; n.twd = twd;
    n.stw = stw; n.heading = heading;
    n.heel = heel; n.pitch = pitch; n.pressure = pressure;
    n.airTemp = airTemp; n.waterTemp = waterTemp;
    n.vmg = vmg; n.updated = DateTime.now();
    return n;
  }
}

class TackData {
  final DateTime ts;
  final double hdgBefore, hdgAfter, delta;
  TackData({required this.ts, required this.hdgBefore,
            required this.hdgAfter, required this.delta});
  String get type => delta.abs() < 150 ? 'Virement' : 'Empannage';
}

enum InstType {
  sog, stw, cog, hdg,
  awa, aws, twa, tws, twd,
  heel, pressure, airTemp, waterTemp, vmg,
  gps, rawNmea, windRose, tacks,
}

class InstConfig {
  final String id;
  InstType type;
  double x, y, w, h;
  InstConfig({required this.id, required this.type,
              required this.x, required this.y,
              required this.w, required this.h});
  Map<String,dynamic> toJson() =>
    {'id':id,'type':type.name,'x':x,'y':y,'w':w,'h':h};
  factory InstConfig.fromJson(Map<String,dynamic> j) => InstConfig(
    id:j['id'], type:InstType.values.firstWhere((e)=>e.name==j['type']),
    x:j['x'], y:j['y'], w:j['w'], h:j['h']);
}

// ═══════════════════════════════════════════════════════════
// NMEA PARSER
// ═══════════════════════════════════════════════════════════
class NmeaParser {
  static NmeaData? parse(String raw, NmeaData cur) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (!_chk(s)) return null;
    final p = s.split(',');
    if (p.isEmpty) return null;
    final tag = p[0].replaceAll(r'$','').replaceAll('!','');
    final type = tag.length >= 3 ? tag.substring(tag.length-3) : tag;
    try {
      switch (type) {
        case 'GGA': return _gga(p, cur);
        case 'RMC': return _rmc(p, cur);
        case 'MWV': return _mwv(p, cur);
        case 'MWD': return _mwd(p, cur);
        case 'VHW': return _vhw(p, cur);
        case 'XDR': return _xdr(p, cur);
        case 'MDA': return _mda(p, cur);
        case 'HDT': case 'HDM':
          final n=cur.copy(); n.heading=p.length>1?double.tryParse(p[1]):null; return n;
        case 'VTG':
          final n=cur.copy();
          n.cog=p.length>1?double.tryParse(p[1]):null;
          n.sog=p.length>8?double.tryParse(p[7]):null;
          return n;
        default: return null;
      }
    } catch(_){ return null; }
  }

  static bool _chk(String s) {
    final a = s.lastIndexOf('*');
    if (a < 0) return true;
    final data = s.substring(1, a);
    final exp  = s.substring(a+1).replaceAll('\r','').replaceAll('\n','');
    int c = 0;
    for (int i=0;i<data.length;i++) c ^= data.codeUnitAt(i);
    return c.toRadixString(16).toUpperCase().padLeft(2,'0') ==
           exp.toUpperCase().padLeft(2,'0');
  }

  static NmeaData _gga(List<String> p, NmeaData c) {
    final n=c.copy();
    if (p.length>1) n.utcTime=_ft(p[1]);
    if (p.length>4) n.latitude=_ll(p[2],p[3]);
    if (p.length>6) n.longitude=_ll(p[4],p[5]);
    if (p.length>7) n.gpsStatus=_gq(p[6]);
    if (p.length>8) n.satellites=int.tryParse(p[7]);
    if (p.length>10) n.altitude=double.tryParse(p[9]);
    return n;
  }

  static NmeaData _rmc(List<String> p, NmeaData c) {
    final n=c.copy();
    if (p.length>1) n.utcTime=_ft(p[1]);
    if (p.length>2) n.gpsStatus=p[2]=='A'?'Active':'Void';
    if (p.length>4) n.latitude=_ll(p[3],p[4]);
    if (p.length>6) n.longitude=_ll(p[5],p[6]);
    if (p.length>7) n.sog=double.tryParse(p[7]);
    if (p.length>8) n.cog=double.tryParse(p[8]);
    return n;
  }

  static NmeaData _mwv(List<String> p, NmeaData c) {
    if (p.length<5) return c;
    final n=c.copy();
    final angle=double.tryParse(p[1]);
    final ref=p[2];
    double? spd=double.tryParse(p[3]);
    final u=p[4].split('*')[0];
    if (spd!=null){if(u=='K')spd/=1.852;if(u=='M')spd*=1.94384;}
    if (ref=='R'){n.awa=angle;n.aws=spd;}else{n.twa=angle;n.tws=spd;}
    _vmg(n); return n;
  }

  static NmeaData _mwd(List<String> p, NmeaData c) {
    if (p.length<6) return c;
    final n=c.copy();
    n.twd=double.tryParse(p[1]);
    n.tws=double.tryParse(p[5]);
    _vmg(n); return n;
  }

  static NmeaData _vhw(List<String> p, NmeaData c) {
    if (p.length<7) return c;
    final n=c.copy();
    n.heading=double.tryParse(p[3]);
    n.stw=double.tryParse(p[5]);
    return n;
  }

  static NmeaData _xdr(List<String> p, NmeaData c) {
    final n=c.copy();
    for (int i=1;i+3<p.length;i+=4){
      final t=p[i]; final v=double.tryParse(p[i+1]);
      final nm=p[i+3].split('*')[0].toUpperCase();
      if(t=='A'){if(nm.contains('HEEL')||nm.contains('ROLL'))n.heel=v;
                 if(nm.contains('PITCH'))n.pitch=v;}
      else if(t=='P') n.pressure=v;
      else if(t=='C'){if(nm.contains('WATER')||nm.contains('SEA'))n.waterTemp=v;
                      else n.airTemp??=v;}
    }
    return n;
  }

  static NmeaData _mda(List<String> p, NmeaData c) {
    final n=c.copy();
    if(p.length>3) n.pressure=double.tryParse(p[3]);
    if(p.length>5) n.airTemp=double.tryParse(p[5]);
    if(p.length>7) n.waterTemp=double.tryParse(p[7]);
    return n;
  }

  static void _vmg(NmeaData n) {
    if (n.stw!=null && n.twa!=null) {
      n.vmg = n.stw! * math.cos(n.twa! * math.pi / 180.0);
    }
  }

  static double? _ll(String v, String d) {
    if (v.isEmpty) return null;
    final dl = (d=='N'||d=='S') ? 2 : 3;
    final deg=double.tryParse(v.substring(0,dl));
    final min=double.tryParse(v.substring(dl));
    if (deg==null||min==null) return null;
    double r=deg+min/60.0;
    if (d=='S'||d=='W') r=-r;
    return r;
  }
  static String _ft(String r) => r.length<6?r:
    '${r.substring(0,2)}:${r.substring(2,4)}:${r.substring(4,6)}';
  static String _gq(String q) {
    switch(q){case'1':return'GPS';case'2':return'DGPS';
              case'4':return'RTK Fixed';case'5':return'RTK Float';
              default:return q=='0'?'No fix':'Fix $q';}
  }
}

// ═══════════════════════════════════════════════════════════
// CONNECTION
// ═══════════════════════════════════════════════════════════
enum Proto { tcp, udp }
enum ConnStatus { disconnected, connecting, connected, error }

class ConnConfig {
  final String host; final int port; final Proto proto;
  const ConnConfig({required this.host, required this.port, required this.proto});
}

class NmeaConn {
  ConnStatus _st = ConnStatus.disconnected;
  ConnConfig? _cfg;
  Socket? _tcp;
  RawDatagramSocket? _udp;
  StreamSubscription? _sub;
  final _stCtrl  = StreamController<ConnStatus>.broadcast();
  final _rawCtrl = StreamController<String>.broadcast();

  Stream<ConnStatus> get statusStream   => _stCtrl.stream;
  Stream<String>     get sentenceStream => _rawCtrl.stream;
  ConnStatus         get status         => _st;
  ConnConfig?        get config         => _cfg;

  void _setSt(ConnStatus s){ _st=s; _stCtrl.add(s); }

  Future<void> connect(ConnConfig cfg) async {
    await disconnect(); _cfg=cfg; _setSt(ConnStatus.connecting);
    try {
      if (cfg.proto==Proto.tcp) { await _doTcp(cfg); }
      else                      { await _doUdp(cfg); }
    } catch(_){ _setSt(ConnStatus.error); }
  }

  Future<void> _doTcp(ConnConfig cfg) async {
    _tcp = await Socket.connect(cfg.host, cfg.port,
                                timeout: const Duration(seconds:10));
    _setSt(ConnStatus.connected);
    final buf = StringBuffer();
    _sub = _tcp!.listen(
      (Uint8List bytes){
        buf.write(utf8.decode(bytes, allowMalformed:true));
        final lines = buf.toString().split('\n');
        for (int i=0;i<lines.length-1;i++){
          final l=lines[i].trim(); if(l.isNotEmpty) _rawCtrl.add(l);
        }
        buf.clear(); buf.write(lines.last);
      },
      onError:(_)=>_setSt(ConnStatus.error),
      onDone: ()=>_setSt(ConnStatus.disconnected),
    );
  }

  Future<void> _doUdp(ConnConfig cfg) async {
    _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, cfg.port);
    _setSt(ConnStatus.connected);
    _sub = _udp!.listen((RawSocketEvent ev){
      if (ev==RawSocketEvent.read){
        final dg=_udp!.receive();
        if (dg!=null){
          for (final l in utf8.decode(dg.data,allowMalformed:true).split('\n')){
            final t=l.trim(); if(t.isNotEmpty) _rawCtrl.add(t);
          }
        }
      }
    });
  }

  Future<void> disconnect() async {
    await _sub?.cancel(); _sub=null;
    _tcp?.destroy(); _tcp=null;
    _udp?.close(); _udp=null;
    _setSt(ConnStatus.disconnected);
  }

  void dispose(){ disconnect(); _stCtrl.close(); _rawCtrl.close(); }
}

// ═══════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════
class DashProvider extends ChangeNotifier {
  final _conn = NmeaConn();
  StreamSubscription? _sentSub, _stSub;
  NmeaData   _data    = NmeaData();
  ConnStatus _connSt  = ConnStatus.disconnected;
  ConnConfig _connCfg = const ConnConfig(host:'192.168.1.1',port:10110,proto:Proto.tcp);
  final List<String>   _raw   = [];
  final List<TackData> _tacks = [];
  double? _prevHdg; DateTime? _prevHdgT;
  bool _rec = false;
  List<InstConfig> _insts = _defaults();

  NmeaData         get data       => _data;
  ConnStatus       get connStatus => _connSt;
  ConnConfig       get connCfg    => _connCfg;
  List<String>     get raw        => List.unmodifiable(_raw);
  List<TackData>   get tacks      => List.unmodifiable(_tacks);
  bool             get recording  => _rec;
  List<InstConfig> get insts      => _insts;

  DashProvider() {
    _stSub  = _conn.statusStream.listen((s){ _connSt=s; notifyListeners(); });
    _sentSub= _conn.sentenceStream.listen(_onSent);
    _load();
  }

  void _onSent(String s){
    _raw.insert(0,s); if(_raw.length>200) _raw.removeLast();
    final u=NmeaParser.parse(s,_data);
    if(u!=null){ _data=u; _detectTack(_data.heading??_data.cog); notifyListeners(); }
  }

  void _detectTack(double? hdg){
    if(hdg==null) return;
    final now=DateTime.now();
    if(_prevHdg!=null&&_prevHdgT!=null){
      final elapsed=now.difference(_prevHdgT!).inSeconds;
      if(elapsed>0&&elapsed<60){
        double d=hdg-_prevHdg!;
        while(d>180)d-=360; while(d<-180)d+=360;
        if(d.abs()>60){
          _tacks.add(TackData(ts:now,hdgBefore:_prevHdg!,hdgAfter:hdg,delta:d));
          if(_tacks.length>100) _tacks.removeAt(0);
        }
      }
    }
    _prevHdg=hdg; _prevHdgT=now;
  }

  Future<void> connect()    async => _conn.connect(_connCfg);
  Future<void> disconnect() async => _conn.disconnect();

  void updateCfg({String? host, int? port, Proto? proto}){
    _connCfg=ConnConfig(host:host??_connCfg.host,port:port??_connCfg.port,
                        proto:proto??_connCfg.proto);
    _save(); notifyListeners();
  }

  void startRec(){ _rec=true;  notifyListeners(); }
  void stopRec() { _rec=false; notifyListeners(); }
  void clearTacks(){ _tacks.clear(); notifyListeners(); }

  void moveInst(String id, double x, double y){
    final i=_insts.indexWhere((e)=>e.id==id);
    if(i>=0){ _insts[i].x=x; _insts[i].y=y; _save(); notifyListeners(); }
  }
  void addInst(InstType t){
    _insts.add(InstConfig(id:'i${DateTime.now().millisecondsSinceEpoch}',
      type:t,x:20,y:20,w:180,h:160));
    _save(); notifyListeners();
  }
  void removeInst(String id){ _insts.removeWhere((e)=>e.id==id); _save(); notifyListeners(); }
  void resetLayout(){ _insts=_defaults(); _save(); notifyListeners(); }

  Future<void> _save() async {
    final p=await SharedPreferences.getInstance();
    p.setString('host',_connCfg.host);
    p.setInt('port',_connCfg.port);
    p.setString('proto',_connCfg.proto.name);
    p.setString('insts',jsonEncode(_insts.map((e)=>e.toJson()).toList()));
  }
  Future<void> _load() async {
    final p=await SharedPreferences.getInstance();
    _connCfg=ConnConfig(
      host: p.getString('host')??'192.168.1.1',
      port: p.getInt('port')??10110,
      proto: Proto.values.firstWhere((e)=>e.name==(p.getString('proto')?? 'tcp'),
               orElse:()=>Proto.tcp));
    final j=p.getString('insts');
    if(j!=null){ try{ _insts=(jsonDecode(j) as List).map((e)=>InstConfig.fromJson(e)).toList(); }catch(_){} }
    notifyListeners();
  }

  static List<InstConfig> _defaults()=>[
    InstConfig(id:'sog',  type:InstType.sog, x:10,  y:10,  w:180,h:160),
    InstConfig(id:'stw',  type:InstType.stw, x:200, y:10,  w:180,h:160),
    InstConfig(id:'awa',  type:InstType.awa, x:390, y:10,  w:180,h:160),
    InstConfig(id:'aws',  type:InstType.aws, x:580, y:10,  w:180,h:160),
    InstConfig(id:'twa',  type:InstType.twa, x:770, y:10,  w:180,h:160),
    InstConfig(id:'tws',  type:InstType.tws, x:960, y:10,  w:180,h:160),
    InstConfig(id:'cog',  type:InstType.cog, x:10,  y:180, w:180,h:160),
    InstConfig(id:'heel', type:InstType.heel,x:200, y:180, w:180,h:160),
    InstConfig(id:'vmg',  type:InstType.vmg, x:390, y:180, w:180,h:160),
    InstConfig(id:'gps',  type:InstType.gps, x:580, y:180, w:370,h:160),
    InstConfig(id:'raw',  type:InstType.rawNmea,  x:10,  y:350, w:480,h:220),
    InstConfig(id:'rose', type:InstType.windRose, x:500, y:350, w:240,h:220),
    InstConfig(id:'tacks',type:InstType.tacks,    x:750, y:350, w:400,h:220),
  ];

  @override
  void dispose(){ _sentSub?.cancel(); _stSub?.cancel(); _conn.dispose(); super.dispose(); }
}

// ═══════════════════════════════════════════════════════════
// WIDGETS
// ═══════════════════════════════════════════════════════════
class NumBox extends StatelessWidget {
  final String label, unit; final double? value;
  final int dec; final Color color;
  const NumBox({super.key,required this.label,required this.unit,
    this.value,this.dec=1,this.color=kText});
  @override Widget build(BuildContext ctx)=>_card(Column(
    mainAxisAlignment:MainAxisAlignment.center, children:[
      Text(label,style:const TextStyle(color:kDim,fontSize:13,letterSpacing:1.5,fontWeight:FontWeight.w600)),
      const SizedBox(height:6),
      Text(value!=null?value!.toStringAsFixed(dec):'---',
        style:TextStyle(color:color,fontSize:36,fontWeight:FontWeight.w700)),
      Text(unit,style:const TextStyle(color:kDim,fontSize:13)),
    ]));
}

class WindAngleBox extends StatelessWidget {
  final String label; final double? value; final bool tw;
  const WindAngleBox({super.key,required this.label,this.value,this.tw=false});
  @override Widget build(BuildContext ctx){
    final c=tw?kGreen:kALight;
    final side=value!=null?(value!>180?'PORT':'STBD'):'';
    final sc=value!=null?(value!>180?kRed:kGreen):kDim;
    return _card(Column(mainAxisAlignment:MainAxisAlignment.center,children:[
      Text(label,style:const TextStyle(color:kDim,fontSize:13,letterSpacing:1.5)),
      const SizedBox(height:4),
      Text(value!=null?'${value!.toStringAsFixed(0)}°':'---',
        style:TextStyle(color:c,fontSize:36,fontWeight:FontWeight.w700)),
      Text(side,style:TextStyle(color:sc,fontSize:14,fontWeight:FontWeight.bold,letterSpacing:2)),
    ]));
  }
}

class HeelBox extends StatelessWidget {
  final double? heel, pitch;
  const HeelBox({super.key,this.heel,this.pitch});
  @override Widget build(BuildContext ctx)=>_card(Column(
    mainAxisAlignment:MainAxisAlignment.center, children:[
      const Text('GÎTE / TANGAGE',style:TextStyle(color:kDim,fontSize:11,letterSpacing:1.5)),
      const SizedBox(height:6),
      SizedBox(width:120,height:70,child:CustomPaint(painter:_HeelPaint(heel??0))),
      const SizedBox(height:4),
      Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
        _sv('GÎTE',heel), _sv('TANGAGE',pitch),
      ]),
    ]));
  Widget _sv(String l,double? v)=>Column(children:[
    Text(l,style:const TextStyle(color:kDim,fontSize:10)),
    Text(v!=null?'${v.toStringAsFixed(1)}°':'--',
      style:const TextStyle(color:kText,fontSize:15,fontWeight:FontWeight.bold)),
  ]);
}

class _HeelPaint extends CustomPainter {
  final double heel;
  _HeelPaint(this.heel);
  @override void paint(Canvas c,Size s){
    final cx=s.width/2,cy=s.height/2,r=math.min(cx,cy)-4;
    c.drawCircle(Offset(cx,cy),r,Paint()..color=kBorder..style=PaintingStyle.stroke..strokeWidth=1.5);
    c.save(); c.translate(cx,cy); c.rotate(heel*math.pi/180);
    c.drawLine(Offset(-r*.7,0),Offset(r*.7,0),
      Paint()..color=kALight..strokeWidth=3..strokeCap=StrokeCap.round);
    c.drawLine(Offset(0,0),Offset(0,-r*.8),Paint()..color=kYellow..strokeWidth=2);
    c.restore();
  }
  @override bool shouldRepaint(_HeelPaint o)=>o.heel!=heel;
}

class GpsBox extends StatelessWidget {
  final NmeaData d;
  const GpsBox({super.key,required this.d});
  String _fmt(double? v,bool lat){
    if(v==null)return '--';
    final a=v.abs();final deg=a.floor();final min=(a-deg)*60;
    final dir=lat?(v>=0?'N':'S'):(v>=0?'E':'W');
    return '$deg° ${min.toStringAsFixed(3)}\' $dir';
  }
  @override Widget build(BuildContext ctx){
    final ok=d.gpsStatus=='Active'||(d.gpsStatus?.startsWith('GPS')??false);
    return _card(Padding(padding:const EdgeInsets.all(10),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,
        mainAxisAlignment:MainAxisAlignment.center,children:[
        Row(children:[
          const Text('GPS',style:TextStyle(color:kDim,fontSize:12,letterSpacing:1.5)),
          const SizedBox(width:8),
          Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
            decoration:BoxDecoration(color:(ok?kGreen:kRed).withOpacity(.2),
              borderRadius:BorderRadius.circular(4),
              border:Border.all(color:(ok?kGreen:kRed).withOpacity(.5))),
            child:Text(d.gpsStatus??'No fix',style:TextStyle(
              color:ok?kGreen:kRed,fontSize:11,fontWeight:FontWeight.bold))),
          if(d.satellites!=null)...[const SizedBox(width:8),
            Text('${d.satellites} sat',style:const TextStyle(color:kDim,fontSize:11))],
        ]),
        const SizedBox(height:6),
        _row(Icons.north,_fmt(d.latitude,true)),
        const SizedBox(height:3),
        _row(Icons.east,_fmt(d.longitude,false)),
        if(d.utcTime!=null)...[const SizedBox(height:3),
          _row(Icons.access_time,d.utcTime!)],
      ])));
  }
  Widget _row(IconData ic,String v)=>Row(children:[
    Icon(ic,color:kDim,size:14),const SizedBox(width:6),
    Text(v,style:const TextStyle(color:kText,fontSize:14,fontWeight:FontWeight.w600))]);
}

class RawBox extends StatelessWidget {
  final List<String> lines;
  const RawBox({super.key,required this.lines});
  Color _c(String s){
    if(s.contains('GGA')||s.contains('RMC'))return kALight;
    if(s.contains('MWV')||s.contains('MWD'))return kGreen;
    if(s.contains('VHW'))return kYellow;
    if(s.contains('XDR')||s.contains('MDA'))return const Color(0xFFFF9F43);
    return kDim;
  }
  @override Widget build(BuildContext ctx)=>Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[
    Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),
      child:Row(children:[
        const Text('NMEA RAW',style:TextStyle(color:kDim,fontSize:12,letterSpacing:1.5)),
        const Spacer(),
        Text('${lines.length}',style:const TextStyle(color:kDim,fontSize:11)),
      ])),
    const Divider(color:kBorder,height:1),
    Expanded(child:lines.isEmpty
      ?const Center(child:Text('En attente...',style:TextStyle(color:kDim)))
      :ListView.builder(
        padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),
        itemCount:lines.length,
        itemBuilder:(_,i)=>Text(lines[i],
          style:TextStyle(color:_c(lines[i]),fontSize:11,fontFamily:'monospace'),
          maxLines:1,overflow:TextOverflow.ellipsis))),
  ]);
}

class WindRoseBox extends StatelessWidget {
  final double? twa, awa;
  const WindRoseBox({super.key,this.twa,this.awa});
  @override Widget build(BuildContext ctx)=>Column(children:[
    const Padding(padding:EdgeInsets.only(top:8),
      child:Text('ROSE DES VENTS',style:TextStyle(color:kDim,fontSize:11,letterSpacing:1.5))),
    Expanded(child:CustomPaint(painter:_RosePaint(twa:twa,awa:awa),child:Container())),
  ]);
}

class _RosePaint extends CustomPainter {
  final double? twa, awa;
  _RosePaint({this.twa,this.awa});
  @override void paint(Canvas c,Size s){
    final cx=s.width/2,cy=s.height/2,r=math.min(cx,cy)-12;
    for(int i=1;i<=3;i++) c.drawCircle(Offset(cx,cy),r*i/3,
      Paint()..color=kBorder..style=PaintingStyle.stroke..strokeWidth=.8);
    for(final e in [('N',-math.pi/2),('E',0.0),('S',math.pi/2),('W',math.pi)]){
      final x=cx+(r+12)*math.cos(e.$2),y=cy+(r+12)*math.sin(e.$2);
      final tp=TextPainter(text:TextSpan(text:e.$1,
        style:const TextStyle(color:kDim,fontSize:11,fontWeight:FontWeight.bold)),
        textDirection:TextDirection.ltr)..layout();
      tp.paint(c,Offset(x-tp.width/2,y-tp.height/2));
    }
    if(twa!=null) _arr(c,cx,cy,r*.8,twa!*math.pi/180-math.pi/2,kGreen,3);
    if(awa!=null) _arr(c,cx,cy,r*.6,awa!*math.pi/180-math.pi/2,kALight,2);
    c.drawCircle(Offset(cx,cy),4,Paint()..color=kText);
  }
  void _arr(Canvas c,double cx,double cy,double len,double a,Color col,double w){
    final ex=cx+len*math.cos(a),ey=cy+len*math.sin(a);
    final p=Paint()..color=col..strokeWidth=w..strokeCap=StrokeCap.round;
    c.drawLine(Offset(cx,cy),Offset(ex,ey),p);
    c.drawLine(Offset(ex,ey),Offset(ex-12*math.cos(a-.4),ey-12*math.sin(a-.4)),p);
    c.drawLine(Offset(ex,ey),Offset(ex-12*math.cos(a+.4),ey-12*math.sin(a+.4)),p);
  }
  @override bool shouldRepaint(_RosePaint o)=>o.twa!=twa||o.awa!=awa;
}

class TacksBox extends StatelessWidget {
  final List<TackData> tacks;
  const TacksBox({super.key,required this.tacks});
  @override Widget build(BuildContext ctx)=>Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[
    Padding(padding:const EdgeInsets.fromLTRB(12,8,12,4),
      child:Row(children:[
        const Text('VIREMENTS',style:TextStyle(color:kDim,fontSize:12,letterSpacing:1.5)),
        const Spacer(),Text('${tacks.length}',style:const TextStyle(color:kDim,fontSize:11)),
      ])),
    const Divider(color:kBorder,height:1),
    tacks.isEmpty
      ?const Expanded(child:Center(child:Text('Aucun virement',style:TextStyle(color:kDim))))
      :Expanded(child:ListView.builder(
        padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
        itemCount:tacks.length,
        itemBuilder:(_,i){
          final t=tacks[tacks.length-1-i];
          final port=t.delta<0; final col=port?kRed:kGreen;
          return Container(margin:const EdgeInsets.symmetric(vertical:2),
            padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
            decoration:BoxDecoration(color:col.withOpacity(.08),
              borderRadius:BorderRadius.circular(6),
              border:Border.all(color:col.withOpacity(.3))),
            child:Row(children:[
              Icon(port?Icons.turn_left:Icons.turn_right,color:col,size:16),
              const SizedBox(width:4),
              Text(t.type,style:TextStyle(color:col,fontSize:12,fontWeight:FontWeight.bold)),
              const SizedBox(width:6),
              Text('${t.hdgBefore.toStringAsFixed(0)}°→${t.hdgAfter.toStringAsFixed(0)}°',
                style:const TextStyle(color:kText,fontSize:11)),
              const Spacer(),
              Text('Δ${t.delta.abs().toStringAsFixed(0)}°',
                style:TextStyle(color:col,fontSize:12,fontWeight:FontWeight.bold)),
            ]));
        })),
  ]);
}

Widget _card(Widget child,[bool edit=false])=>Container(
  decoration:BoxDecoration(color:kCard,borderRadius:BorderRadius.circular(12),
    border:Border.all(color:edit?kAccent.withOpacity(.6):kBorder)),
  child:child);

// ═══════════════════════════════════════════════════════════
// CONNECTION DIALOG
// ═══════════════════════════════════════════════════════════
class ConnDialog extends StatefulWidget {
  const ConnDialog({super.key});
  @override State<ConnDialog> createState()=>_ConnDialogState();
}
class _ConnDialogState extends State<ConnDialog>{
  late TextEditingController _host,_port;
  Proto _proto=Proto.tcp;
  @override void initState(){
    super.initState();
    final p=context.read<DashProvider>();
    _host=TextEditingController(text:p.connCfg.host);
    _port=TextEditingController(text:p.connCfg.port.toString());
    _proto=p.connCfg.proto;
  }
  @override void dispose(){ _host.dispose(); _port.dispose(); super.dispose(); }
  @override Widget build(BuildContext ctx)=>Dialog(
    backgroundColor:kCard,
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
    child:Container(width:400,padding:const EdgeInsets.all(24),
      child:Column(mainAxisSize:MainAxisSize.min,
        crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Connexion NMEA',style:TextStyle(color:kText,fontSize:20,fontWeight:FontWeight.bold)),
        const SizedBox(height:16),
        Row(children:[
          _pb('TCP',_proto==Proto.tcp,()=>setState(()=>_proto=Proto.tcp)),
          const SizedBox(width:12),
          _pb('UDP',_proto==Proto.udp,()=>setState(()=>_proto=Proto.udp)),
        ]),
        const SizedBox(height:14),
        if(_proto==Proto.tcp)...[
          const Text('Hôte',style:TextStyle(color:kDim,fontSize:13)),
          const SizedBox(height:6), _tf(_host,'192.168.1.1'),
          const SizedBox(height:12),
        ],
        const Text('Port',style:TextStyle(color:kDim,fontSize:13)),
        const SizedBox(height:6), _tf(_port,'10110',num:true),
        const SizedBox(height:20),
        Row(mainAxisAlignment:MainAxisAlignment.end,children:[
          TextButton(onPressed:()=>Navigator.pop(ctx),
            child:const Text('Annuler',style:TextStyle(color:kDim))),
          const SizedBox(width:12),
          ElevatedButton(
            style:ElevatedButton.styleFrom(backgroundColor:kAccent,
              shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8))),
            onPressed:(){
              final p=context.read<DashProvider>();
              p.updateCfg(host:_host.text.trim(),
                port:int.tryParse(_port.text.trim())??10110,proto:_proto);
              p.connect(); Navigator.pop(ctx);
            },
            child:const Text('Connecter',style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold))),
        ]),
      ])));

  Widget _pb(String l,bool sel,VoidCallback t)=>GestureDetector(onTap:t,
    child:Container(padding:const EdgeInsets.symmetric(horizontal:20,vertical:8),
      decoration:BoxDecoration(color:sel?kAccent:kSurface,
        borderRadius:BorderRadius.circular(8),
        border:Border.all(color:sel?kAccent:kBorder)),
      child:Text(l,style:TextStyle(color:sel?Colors.white:kDim,fontWeight:FontWeight.bold))));

  Widget _tf(TextEditingController c,String h,{bool num=false})=>TextField(
    controller:c,keyboardType:num?TextInputType.number:TextInputType.text,
    style:const TextStyle(color:kText,fontFamily:'monospace'),
    decoration:InputDecoration(hintText:h,hintStyle:const TextStyle(color:kDim),
      filled:true,fillColor:kSurface,
      border:OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:const BorderSide(color:kBorder)),
      enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:const BorderSide(color:kBorder)),
      focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:const BorderSide(color:kAccent)),
      contentPadding:const EdgeInsets.symmetric(horizontal:14,vertical:12)));
}

// ═══════════════════════════════════════════════════════════
// DRAGGABLE INSTRUMENT
// ═══════════════════════════════════════════════════════════
class DragInst extends StatefulWidget {
  final InstConfig cfg; final NmeaData data; final bool edit;
  const DragInst({super.key,required this.cfg,required this.data,required this.edit});
  @override State<DragInst> createState()=>_DragInstState();
}
class _DragInstState extends State<DragInst>{
  late double _x,_y; double _sx=0,_sy=0;
  @override void initState(){ super.initState(); _x=widget.cfg.x; _y=widget.cfg.y; }

  Widget _content(BuildContext ctx){
    final d=widget.data;
    final p=context.watch<DashProvider>();
    switch(widget.cfg.type){
      case InstType.sog:  return NumBox(label:'SOG',unit:'kt',value:d.sog,dec:1);
      case InstType.stw:  return NumBox(label:'STW',unit:'kt',value:d.stw,dec:1);
      case InstType.cog:  return NumBox(label:'COG',unit:'°', value:d.cog,dec:0);
      case InstType.hdg:  return NumBox(label:'HDG',unit:'°', value:d.heading,dec:0);
      case InstType.awa:  return WindAngleBox(label:'AWA',value:d.awa);
      case InstType.aws:  return NumBox(label:'AWS',unit:'kt',value:d.aws,color:kALight);
      case InstType.twa:  return WindAngleBox(label:'TWA',value:d.twa,tw:true);
      case InstType.tws:  return NumBox(label:'TWS',unit:'kt',value:d.tws,color:kGreen);
      case InstType.twd:  return NumBox(label:'TWD',unit:'°', value:d.twd,dec:0);
      case InstType.heel: return HeelBox(heel:d.heel,pitch:d.pitch);
      case InstType.pressure: return NumBox(label:'BARO',unit:'hPa',value:d.pressure,dec:0);
      case InstType.airTemp:  return NumBox(label:'AIR', unit:'°C', value:d.airTemp);
      case InstType.waterTemp:return NumBox(label:'MER', unit:'°C', value:d.waterTemp,color:const Color(0xFF00B4D8));
      case InstType.vmg:  return NumBox(label:'VMG',unit:'kt',value:d.vmg,dec:2,color:kYellow);
      case InstType.gps:  return GpsBox(d:d);
      case InstType.rawNmea: return RawBox(lines:p.raw);
      case InstType.windRose:return WindRoseBox(twa:d.twa,awa:d.awa);
      case InstType.tacks:   return TacksBox(tacks:p.tacks);
    }
  }

  @override Widget build(BuildContext ctx){
    final c=widget.cfg;
    return Positioned(left:_x,top:_y,
      child:GestureDetector(
        onPanStart:widget.edit?(d){_sx=d.globalPosition.dx-_x;_sy=d.globalPosition.dy-_y;}:null,
        onPanUpdate:widget.edit?(d){setState((){_x=d.globalPosition.dx-_sx;_y=d.globalPosition.dy-_sy;});}:null,
        onPanEnd:widget.edit?(_){ctx.read<DashProvider>().moveInst(c.id,_x,_y);}:null,
        child:Container(width:c.w,height:c.h,
          decoration:BoxDecoration(color:kCard,borderRadius:BorderRadius.circular(12),
            border:Border.all(color:widget.edit?kAccent.withOpacity(.5):kBorder),
            boxShadow:[BoxShadow(color:Colors.black.withOpacity(.3),blurRadius:6,offset:const Offset(0,3))]),
          child:Stack(children:[
            _content(ctx),
            if(widget.edit)...[
              Positioned(top:3,left:6,child:Icon(Icons.drag_indicator,color:kALight.withOpacity(.6),size:16)),
              Positioned(top:3,right:3,child:GestureDetector(
                onTap:()=>ctx.read<DashProvider>().removeInst(c.id),
                child:Container(width:20,height:20,
                  decoration:BoxDecoration(color:kRed.withOpacity(.8),shape:BoxShape.circle),
                  child:const Icon(Icons.close,color:Colors.white,size:13)))),
            ],
          ]))));
  }
}

// ═══════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════
class DashScreen extends StatefulWidget {
  const DashScreen({super.key});
  @override State<DashScreen> createState()=>_DashScreenState();
}
class _DashScreenState extends State<DashScreen>{
  bool _edit=false, _addPanel=false;

  static const _addItems=[
    (InstType.sog,'SOG',Icons.speed),(InstType.stw,'STW',Icons.water),
    (InstType.awa,'AWA',Icons.air),(InstType.aws,'AWS',Icons.air),
    (InstType.twa,'TWA',Icons.air),(InstType.tws,'TWS',Icons.air),
    (InstType.twd,'TWD',Icons.navigation),(InstType.cog,'COG',Icons.explore),
    (InstType.hdg,'HDG',Icons.compass_calibration),(InstType.heel,'GÎTE',Icons.rotate_90_degrees_ccw),
    (InstType.pressure,'BARO',Icons.thermostat),(InstType.airTemp,'AIR°C',Icons.wb_sunny),
    (InstType.waterTemp,'MER°C',Icons.pool),(InstType.vmg,'VMG',Icons.trending_up),
    (InstType.gps,'GPS',Icons.gps_fixed),(InstType.rawNmea,'NMEA',Icons.terminal),
    (InstType.windRose,'ROSE',Icons.donut_large),(InstType.tacks,'VIRT.',Icons.swap_horiz),
  ];

  @override Widget build(BuildContext ctx){
    final p=context.watch<DashProvider>();
    return Scaffold(backgroundColor:kBg,body:Column(children:[
      _topBar(p),
      if(_edit&&_addPanel) _addRow(p),
      Expanded(child:InteractiveViewer(constrained:false,scaleEnabled:false,
        child:SizedBox(width:1400,height:900,
          child:Stack(children:p.insts.map((c)=>DragInst(
            key:ValueKey(c.id),cfg:c,data:p.data,edit:_edit)).toList())))),
    ]));
  }

  Widget _topBar(DashProvider p){
    final s=p.connStatus;
    final col=s==ConnStatus.connected?kGreen:s==ConnStatus.connecting?kYellow:s==ConnStatus.error?kRed:kDim;
    final lbl=s==ConnStatus.connected?'CONNECTÉ':s==ConnStatus.connecting?'CONNEXION...':s==ConnStatus.error?'ERREUR':'DÉCO.';
    return Container(height:52,
      decoration:const BoxDecoration(color:kSurface,border:Border(bottom:BorderSide(color:kBorder))),
      padding:const EdgeInsets.symmetric(horizontal:14),
      child:Row(children:[
        const Icon(Icons.sailing,color:kALight,size:22),
        const SizedBox(width:8),
        const Text('NauticDash',style:TextStyle(color:kText,fontSize:17,fontWeight:FontWeight.bold)),
        const SizedBox(width:16),
        GestureDetector(
          onTap:()=>showDialog(context:context,builder:(_)=>ChangeNotifierProvider.value(value:p,child:const ConnDialog())),
          child:Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
            decoration:BoxDecoration(color:col.withOpacity(.1),borderRadius:BorderRadius.circular(6),
              border:Border.all(color:col.withOpacity(.4))),
            child:Row(mainAxisSize:MainAxisSize.min,children:[
              Container(width:7,height:7,decoration:BoxDecoration(color:col,shape:BoxShape.circle)),
              const SizedBox(width:6),
              Text(lbl,style:TextStyle(color:col,fontSize:12,fontWeight:FontWeight.bold)),
              const SizedBox(width:4),
              Text('${p.connCfg.proto.name.toUpperCase()} ${p.connCfg.host}:${p.connCfg.port}',
                style:const TextStyle(color:kDim,fontSize:11)),
            ]))),
        if(s==ConnStatus.disconnected||s==ConnStatus.error)
          _tb(Icons.play_arrow,'Connecter',kGreen,p.connect),
        if(s==ConnStatus.connected)
          _tb(Icons.stop,'Déconnecter',kRed,p.disconnect),
        const Spacer(),
        _tb(p.recording?Icons.stop_circle:Icons.fiber_manual_record,
          p.recording?'Stop':' Trace',p.recording?kRed:kDim,
          p.recording?p.stopRec:p.startRec),
        const SizedBox(width:16),
        if(_edit)...[
          _tb(Icons.add,'Ajouter',_addPanel?kALight:kDim,()=>setState(()=>_addPanel=!_addPanel)),
          const SizedBox(width:8),
          _tb(Icons.refresh,'Reset',kDim,p.resetLayout),
          const SizedBox(width:8),
        ],
        GestureDetector(onTap:()=>setState((){_edit=!_edit;_addPanel=false;}),
          child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
            decoration:BoxDecoration(color:_edit?kAccent.withOpacity(.2):kSurface,
              borderRadius:BorderRadius.circular(8),
              border:Border.all(color:_edit?kAccent:kBorder)),
            child:Row(mainAxisSize:MainAxisSize.min,children:[
              Icon(_edit?Icons.check:Icons.grid_view,color:_edit?kALight:kDim,size:16),
              const SizedBox(width:5),
              Text(_edit?'Terminer':'Éditer',style:TextStyle(color:_edit?kALight:kDim,fontSize:13)),
            ]))),
      ]));
  }

  Widget _tb(IconData ic,String l,Color col,VoidCallback fn)=>
    Padding(padding:const EdgeInsets.only(left:8),
      child:GestureDetector(onTap:fn,
        child:Row(mainAxisSize:MainAxisSize.min,children:[
          Icon(ic,color:col,size:16),const SizedBox(width:4),
          Text(l,style:TextStyle(color:col,fontSize:12))])));

  Widget _addRow(DashProvider p)=>Container(height:58,color:kSurface,
    padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),
    child:ListView(scrollDirection:Axis.horizontal,
      children:_addItems.map((it)=>GestureDetector(
        onTap:()=>p.addInst(it.$1),
        child:Container(margin:const EdgeInsets.only(right:8),
          padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),
          decoration:BoxDecoration(color:kCard,borderRadius:BorderRadius.circular(8),
            border:Border.all(color:kBorder)),
          child:Row(mainAxisSize:MainAxisSize.min,children:[
            Icon(it.$3,color:kALight,size:15),const SizedBox(width:5),
            Text(it.$2,style:const TextStyle(color:kText,fontSize:12))]))
      ).toList()));
}

// ═══════════════════════════════════════════════════════════
// ENTRY POINT
// ═══════════════════════════════════════════════════════════
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(
    ChangeNotifierProvider(
      create: (_) => DashProvider(),
      child: MaterialApp(
        title: 'NauticDash',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kBg,
          colorScheme: const ColorScheme.dark(primary: kAccent, surface: kSurface),
        ),
        home: const DashScreen(),
      ),
    ),
  );
}
