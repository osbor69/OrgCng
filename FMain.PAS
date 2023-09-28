unit FMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, Menus, ExtCtrls, ShellAPI, Math, DateUtils, StrUtils, DB,
  FIBDatabase, pFIBDatabase, FIBQuery, pFIBQuery, FIBDataSet, pFIBDataSet;

const WM_NOTIFYTRAYICON = WM_USER + 1;

type
  TSelIspEnd1 = record
    qtxt: string;
    recno: longint;
  end;

  PSelIspEndArr = ^TSelIspEndArr;
  TSelIspEndArr = record
    a: array of TSelIspEnd1;
    tselispe: TDateTime;
  end;

  TUpdOper = (updNone,updCommit,updRollback);

  TCustomThread = class(TThread)
  private
    tm: TTimer;
    db: TpFIBDatabase;
    nTrns: longint;
    nUpd: TUpdOper;
    qUpd: TpFIBDataSet;
    procedure TimerHide(Sender: TObject);
    procedure TimerScan(Sender: TObject);
    function TrnsStart: boolean;
    procedure TrnsEnd(Connected: boolean);
    procedure Upd(const qtxt: string);
  protected
    procedure Execute; override;
    procedure FTimerScan; virtual; abstract;
  public
    constructor Create(APriority: TThreadPriority); virtual;
  end;

  TCng = class(TCustomThread)
  private
    q: TpFIBDataSet;
  protected
    procedure FTimerScan; override;
  public
    constructor Create(APriority: TThreadPriority); override;
    destructor Destroy; override;
  end;

  TIsp = class(TCustomThread)
  private
    q,q1: TpFIBDataSet;
    lCdrTn: byte;
    sqZaj: string;
    OneMinute: Double;
    procedure FTimer(Sender: TObject);
    function FText(q: TpFIBDataSet; tselispe: Double): string;
    procedure FExec(const r: TSelIspEnd1; tselispe: Double); overload;
    procedure FExec(pa: PSelIspEndArr); overload;
  protected
    procedure FTimerScan; override;
  public
    constructor Create(APriority: TThreadPriority); override;
    destructor Destroy; override;
  end;

  TBot = class(TCustomThread)
  private
    PathIn,PathOut,FilePrm,FileRead,sq: string;
    UserCnt: Word;
    MsgRecno,dFilePrm: longint;
    lMsgTn,CntMsgTxt: byte;
    lsPrm,lsFld: TStringList;
    aVal: array of string;
    procedure SetVal(const nmf: string; const v: variant);
  protected
    procedure FTimerScan; override;
  public
    constructor Create(APriority: TThreadPriority); override;
    destructor Destroy; override;
  end;

  TMain = class(TForm)
    mn: TPopupMenu;
    nExit: TMenuItem;
    nAbout: TMenuItem;
    lbOwner: TLabel;
    lbBuild: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure nExitClick(Sender: TObject);
    procedure nAboutClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    { Private declarations }
	  tray: TNotifyIconData;
    Cng: TCng;
    Isp: TIsp;
    Bot: TBot;
    Admin,DatabaseName: string;
    RepDeadLock: Word;
    class procedure ApplException(Sender: TObject; E: Exception);
  	procedure WMTRAYICONNOTIFY(var Msg: TMessage); message WM_NOTIFYTRAYICON;
  public
    { Public declarations }
  end;

var
  Main: TMain;

procedure FindOtherOrgCng;

implementation

uses IBHeader,
  Shifr,
  OLProc;

{$R *.dfm}

const
  nRECNO    = 0;
  nTCNG     = 1;
  nTSELISPE = 2;
  nTSELISP  = 3;
  nSELISPSH = 4;
  nCNTISP   = 5;
  nWTN      = 6;

  nCNT      = 6;

  CRLF = #13#10;

var lsPrm: TStringList;

function ValStr(const nmp: string): string;
begin
  result:=lsPrm.Values[nmp]; lsPrm.Values[nmp]:='';
end;

procedure FindOtherOrgCng;
const s = 'Учёт клиентов: мониторинг';
var h: HWND;
  OtherQuit: boolean;
begin
  lsPrm:=TStringList.Create;
  lsPrm.LoadFromFile(ExtractFilePath(Application.ExeName)+'ORGCNG.PRM');
  OtherQuit := AnsiUpperCase(ParamStr(1))='/U'; // На нашем сервере прерывание другого приложения не работает
  h:=FindWindow('TApplication',PChar(s));
  if not OtherQuit and (h=0) then begin
    Application.Title:=s;
    Application.CreateForm(TMain, Main)
  end
  else begin
    if OtherQuit and (h<>0) then PostMessage(h,WM_QUIT,0,0);
    Application.Terminate;
  end;
end;

function SpaceStr(const s: string; l: byte): string;
begin
  result:=StringOfChar(' ',l-Length(s))+s;
end;

{ TMain }
procedure TMain.FormCreate(Sender: TObject);
const iX=10; iY=10;
var i: longint;
  InfoSize,Wnd,VerSize: longword;
	VerBuf: Pointer;
  FI: PVSFixedFileInfo;
  sm: TNonClientMetrics;
  Style: TFontStyles;
begin
	{if Win32Platform=VER_PLATFORM_WIN32_NT
  then SetPriorityClass(GetCurrentProcess,HIGH_PRIORITY_CLASS);}
  with tray do begin
    cbSize:=SizeOf(TNotifyIconData); Wnd:=Handle; uID:=1;
    uFlags := NIF_ICON or NIF_MESSAGE or NIF_TIP; uCallBackMessage:=WM_NOTIFYTRAYICON;
    hIcon:=Application.Icon.Handle;
    for i:=1 to Length(Application.Title) do szTip[i-1]:=Application.Title[i];
  end;
  Shell_NotifyIcon(NIM_ADD,@tray);
  InfoSize:=GetFileVersionInfoSize(PChar(Application.ExeName), Wnd);
  if InfoSize <> 0 then begin
    GetMem(VerBuf, InfoSize);
    try
      if GetFileVersionInfo(PChar(Application.ExeName), Wnd, InfoSize, VerBuf) then
        if VerQueryValue(VerBuf, '\', Pointer(FI), VerSize) then begin
        	lbBuild.Visible:=true;
          lbBuild.Caption:='Сборка '+Format('%d.%d.%d.%d',
          	[HiWord(FI.dwFileVersionMS),LoWord(FI.dwFileVersionMS),
            HiWord(FI.dwFileVersionLS),LoWord(FI.dwFileVersionLS)]);
        end;
    finally
      FreeMem(VerBuf);
    end;
  end;
  sm.cbSize:=SizeOf(sm);
  SystemParametersInfo(SPI_GETNONCLIENTMETRICS,sm.cbSize,@sm,0);
  with sm.lfSmCaptionFont, Canvas do begin
    Font.Name := lfFaceName;
    Font.Height := lfHeight;
    Font.Charset := TFontCharset(lfCharSet);
    Style := [];
    if lfWeight > FW_REGULAR then Include(Style, fsBold);
    if lfItalic <> 0 then Include(Style, fsItalic);
    if lfUnderline <> 0 then Include(Style, fsUnderline);
    if lfStrikeOut <> 0 then Include(Style, fsStrikeOut);
    Font.Style:=Style;
    i:=TextWidth(Caption)+10+GetSystemMetrics(SM_CXSMSIZE);
  end;
  ClientWidth := max(lbOwner.Width,lbBuild.Width) + iX shl 1;
  if Width<i then Width:=i;
  ClientHeight:=lbOwner.Height+lbBuild.Height+iY*3;
  lbOwner.SetBounds(trunc((ClientWidth-lbOwner.Width)/2),iY,lbOwner.Width,lbOwner.Height);
  lbBuild.SetBounds(trunc((ClientWidth-lbBuild.Width)/2),iY shl 1 + lbOwner.Height,lbBuild.Width,lbBuild.Height);
  Cng:=TCng.Create(tpNormal);
  Isp:=TIsp.Create(tpHighest);
  Bot:=TBot.Create(tpHigher);
end;

procedure TMain.FormDestroy(Sender: TObject);
begin
  Cng.Free; Isp.Free; Bot.Free; Shell_NotifyIcon(NIM_DELETE,@tray);
end;

procedure TMain.WMTRAYICONNOTIFY(var Msg: TMessage);
var p: TPoint;
begin
  if (Msg.LParam=WM_LBUTTONUP) or (Msg.LParam=WM_RBUTTONUP) then begin
    GetCursorPos(p); {tm.Enabled:=false;} mn.Popup(p.X,p.Y);
  end;
end;

procedure TMain.nExitClick(Sender: TObject);
begin
	Close;
end;

procedure TMain.nAboutClick(Sender: TObject);
begin
	Visible:=true;
end;

procedure TMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
	if (Action=caHide) and Visible then begin
  	Visible:=false; Action:=caNone;
  end;
end;

function qDouble(v: Double): string;
begin
  result:=StringReplace(Trim(VarAsType(v,varString)),DecimalSeparator,'.',[])
end;

function RoundMin(dt: TDateTime): TDateTime;
var y,m,d,h,n,s,z: Word;
begin
  DecodeDateTime(dt,y,m,d,h,n,s,z); result:=EncodeDateTime(y,m,d,h,n,0,0);
end;

function SelIspEndCan(q: TpFIBDataSet): boolean;
begin
  result := (Trim(q.Fields[nSELISPSH].AsString)<>'') and (Trim(q.Fields[nWTN].AsString)='');
end;

class procedure TMain.ApplException;
begin
  Application.MessageBox(PChar(E.Message),PChar(FormatDateTime('dd/mm/yyyy hh:nn:ss:zzz',Now)));
end;

{ TCustomThread }
constructor TCustomThread.Create;
begin
  inherited Create(false);
  Priority:=APriority;
  db:=TpFIBDatabase.Create(Main);
  with db do begin
    DefaultTransaction:=TpFIBTransaction.Create(Main);
    with TpFIBTransaction(DefaultTransaction) do begin
      DefaultDatabase:=db;
      TRParams.Text:='write'+CRLF+'nowait'+CRLF+'rec_version'+CRLF+'read_committed';
    end;
  end;
  qUpd:=TpFIBDataSet.Create(Main); qUpd.Database:=db;
  tm:=TTimer.Create(Main);
  with tm do begin
    Interval:=1; OnTimer:=TimerHide;
  end;
end;

procedure TCustomThread.TimerHide;
begin
	tm.Enabled:=false;
  with Main do if Caption='' then begin
    Visible:=false;
    ValStr('OPERATION');
    Admin:=ValStr('ADMIN');
    RepDeadLock:=StrToIntDef(ValStr('REPDEADLOCK'),0);
    DatabaseName:=ValStr('SERVER_NAME');
    Caption:=Application.Title;
  end;
  db.DatabaseName:=Main.DatabaseName;
  db.DBParams.Assign(lsPrm);
  tm.OnTimer:=TimerScan; tm.Interval:=SecsPerMin*MSecsPerSec; tm.Enabled:=true; tm.OnTimer(tm);
end;

procedure TCustomThread.TimerScan;
var oCon: boolean;
  tm: TTimer;
begin
  tm:=pointer(Sender); tm.Enabled:=false; oCon:=TrnsStart;
  try
    FTimerScan;
  finally
    TrnsEnd(oCon); tm.Enabled:=true;
  end;
end;

function TCustomThread.TrnsStart;
begin
  result:=db.Connected;
  if nTrns=0 then begin
    db.Connected:=true; db.DefaultTransaction.StartTransaction;
  end;
  Inc(nTrns);
end;

procedure TCustomThread.TrnsEnd;
begin
  Dec(nTrns);
  if nTrns=0 then begin
    case nUpd of
      updCommit: db.DefaultTransaction.CommitRetaining;
      updRollBack: db.DefaultTransaction.RollbackRetaining;
    end;
    nUpd:=updNone; db.Connected:=Connected;
  end;
end;

procedure TCustomThread.Upd;
var i: longint;
begin
  if nUpd<>updRollBack then begin
    i:=Main.RepDeadLock;
    while true do
      try
        with qUpd do begin
          SQLs.SelectSQL.Text:=qtxt; QSelect.ExecQuery; nUpd:=updCommit;
        end;
        break;
      except
        on E:EDatabaseError do
          if (i=0) or (Pos('DEADLOCK',AnsiUpperCase(E.Message))=0) then begin
            nUpd:=updRollBack; raise;
          end
          else Dec(i);
      end;
  end;
end;

procedure TCustomThread.Execute;
begin
end;

{ TCng }
constructor TCng.Create;
begin
  inherited;
  q:=TpFIBDataSet.Create(Main);
  with q do begin
    Database:=db;
    SelectSQL.Text:='select KC,ZN,DT from CNGV,MEMO where CNGV.MEM_F=MEMO.GK order by GK,NPP';
  end;
end;

destructor TCng.Destroy;
begin
  q.Close;
  inherited;
end;

procedure TCng.FTimerScan;
var dt: longint;
  procedure MaskFilesProc(const Paths: string; lDir: boolean = true);
    var sr: TSearchRec;
    function NotSysDir: boolean;
    begin
      if (sr.Attr and faDirectory)=faDirectory
      then result:=not((sr.Name[1]='.') and (ExtractFileExt(sr.Name)='.'))
      else result:=true;
    end;
  var i,p: longint;
    s,s1,s2: string;
  begin
    s:=Trim(Paths);
    while s<>'' do begin
      p:=Pos(';',s);
      if p=0 then p:=Length(s)+1;
      s1:=Trim(Copy(s,1,p-1));
      if s1<>'' then begin
        s2:=s1;
        if lDir then begin
          s2:=IncludeTrailingPathDelimiter(s2); s1:=s2+'*.*';
        end;
        i:=SysUtils.FindFirst(s1,faAnyFile-IfThen(not lDir,faDirectory),sr);
        while i=0 do begin
          if Length(sr.Name)>0 then
            if NotSysDir then
              if (sr.Attr and faDirectory)=faDirectory then MaskFilesProc(s2+sr.Name)
              else if not AnsiMatchText(sr.Name,['IND.DFM','DBVAR.DBF','DBPRIZ.DBF']) then dt:=max(dt,sr.Time);
          i:=SysUtils.FindNext(sr);
        end;
        SysUtils.FindClose(sr);
      end;
      s:=Trim(Copy(s,p+1,MaxInt));
    end;
  end;
var kc,zn: string;
  p,odt: longint;
begin
  with q do begin
    Open;
    while not Eof do begin
      kc:=Fields[0].AsString; zn:=''; odt:=Fields[2].AsInteger;
      while not Eof and (Fields[0].AsString=kc) do begin
        zn:=zn+TrimRight(Fields[1].AsString); Next;
      end;
      StrDeshifrSelf(zn); p:=Pos(#31,zn); dt:=0;
      if p>0 then begin
        MaskFilesProc(Copy(zn,p+1,MaxInt),false); // Файлы
        SetLength(zn,p-1);
      end;
      MaskFilesProc(zn); // Папки
      if dt>0 then begin
        if odt>0 then
          if dt>odt then Upd('update CNG set SEL=''T'' where KC='''+kc+'''') else dt:=0;
      end;
      if dt>0 then Upd('update CNGV set DT='+IntToStr(dt)+' where KC='''+kc+'''');
    end;
    Close;
  end;
end;

{ TIsp }
constructor TIsp.Create;
const af: array[0..nCNT] of string = ('RECNO','TCNG','TSELISPE','TSELISP','SELISPSH','CNTISP','WTN');
var i: byte;
begin
  inherited;
  q:=TpFIBDataSet.Create(Main);
  with q do begin
    Database:=db;
    SelectSQL.Text:='select TN from CDR';
  end;
  q1:=TpFIBDataSet.Create(Main); q1.Database:=db;
  sqZaj:='';
  for i:=low(af) to high(af) do sqZaj:=sqZaj+','+af[i];
  sqZaj:='select '+Copy(sqZaj,2,MaxInt)+' from ZAJ where ';
  OneMinute:=EncodeTime(0,1,0,0);
end;

destructor TIsp.Destroy;
begin
  q.Close;
  inherited;
end;

procedure TIsp.FTimerScan;
var dn: TDateTime;
  s0,s1,s2: string;
  pa: PSelIspEndArr;
	p: longint;
  h,n,s,z: Word;
begin
  with q do begin
    if lCdrTn=0 then begin
      Open; lCdrTn:=Fields[0].Size; Close;
    end;
    dn:=RoundMin(Now);          s0:=DateToString(dn);
    dn:=RoundMin(dn+OneMinute); s1:=DateToString(dn);
                                s2:=DateToString(RoundMin(dn+OneMinute));
    SQLs.SelectSQL.Text:=sqZaj+'TSELISPE<>'''' and TSELISPE<'''+s2+'''';
    Open;
    if not Eof then begin
      New(pa); pa.tselispe:=dn; Last; SetLength(pa.a,RecordCount); First; p:=0;
      while not Eof do begin
        pa.a[p].qtxt:=FText(q,dn)+' and TCNG='+qDouble(Fields[nTCNG].AsFloat);
        pa.a[p].recno:=Fields[nRECNO].AsInteger;
        if Fields[nTSELISPE].AsString<s1 then begin
          if SelIspEndCan(q) then FExec(pa.a[p],dn);
        end
        else if Fields[nTSELISP].AsString>=s0 then begin
          if SelIspEndCan(q) then Upd('update ZAJ set TSELISPE='''+s2+''' where RECNO='+IntToStr(pa.a[p].recno));
        end
        else Inc(p);
        Next;
      end;
      SetLength(pa.a,p); dn:=dn-Now;
      if dn<0
        then FExec(pa)
      else if p=0
        then Dispose(pa)
      else with TTimer.Create(Main) do begin
        Tag:=longint(pa);
        DecodeTime(dn,h,n,s,z); Interval:=z+MSecsPerSec*(s+SecsPerMin*(n+MinsPerHour*h));
        OnTimer:=FTimer;
      end;
    end;
    Close;
  end;
end;

procedure TIsp.FTimer;
var pa: PSelIspEndArr;
begin
  with TTimer(Sender) do begin
    Enabled:=false; pa:=PSelIspEndArr(Tag); Free; FExec(pa);
  end;
end;

function TIsp.FText;
var wtn,twtn: string;
  ball0: Int64;
  tcng: Double;
begin
  with q do begin
    SelIspEnd(wtn,twtn,ball0,tcng,tselispe,Fields[nSELISPSH].AsString,Fields[nCNTISP].AsInteger,Main.Admin);
    result:='update ZAJ set WTN='''+SpaceStr(wtn,lCdrTn)+''',BALL0='+IntToStr(ball0)+',TWTN='''+twtn+''',TCNG='+qDouble(tcng)
      +' where RECNO='+IntToStr(Fields[nRECNO].AsInteger)
      +' and not(SELISPSH='''' or SELISPSH is null) and WTN='''' and TISPD=''''';
  end;
end;

procedure TIsp.FExec(const r: TSelIspEnd1; tselispe: Double);
begin
  Upd(r.qtxt);
  if qUpd.QSelect.RowsAffected=0 then with q1 do begin
    SQLs.SelectSQL.Text:=sqZaj+'RECNO='+IntToStr(r.recno); Open;
    if SelIspEndCan(q1) then
      if Fields[nTSELISPE].AsString=DateToString(tselispe) then
        if Fields[nTSELISP].AsString>=DateToString(RoundMin(tselispe-OneMinute))
        then Upd('update ZAJ set TSELISPE='''+DateToString(RoundMin(tselispe+OneMinute))
          +''' where RECNO='+IntToStr(r.recno))
        else Upd(FText(q1,tselispe));
    Close;
  end;
end;

procedure TIsp.FExec(pa: PSelIspEndArr);
var i: longint;
  oCon: boolean;
begin
  with pa^ do if Length(a)>0 then begin
    oCon:=TrnsStart;
    try
      for i:=low(a) to high(a) do FExec(a[i],tselispe);
    finally
      TrnsEnd(oCon);
    end;
  end;
  Dispose(pa);
end;

{ TBot }
constructor TBot.Create;
begin
  inherited;
  lsPrm:=TStringList.Create; lsFld:=TStringList.Create;
end;

destructor TBot.Destroy;
begin
  lsPrm.Free; lsFld.Free;
  inherited;
end;

procedure PrSplitTxt254(const av: array of variant; const nmf,txt: string);
begin
  TBot(longint(av[0])).SetVal(nmf,txt);
end;

procedure TBot.FTimerScan;
var fn: string;
  j: longint;
  function Part: string;
  var p: longint;
  begin
    p:=PosEx('_',fn,j);
    if p=0 then p:=Length(fn)+1;
    result:=Copy(fn,j,p-j); j:=p+1;
  end;
  function fReadDel(const FileName: TFileName; var s: string): boolean;
  begin
    s:=GetStrFile(FileName,MaxInt,@result); DeleteFile(FileName);
  end;
var i: longint;
  sr: TSearchRec;
  UserNum: Word;
  s,tnto,td1,fio,id,txt: string;
  d1: TDateTime;
begin
  if UserCnt=0 then begin
    with TpFIBDataSet.Create(Main) do try
      Database:=db;
      SelectSQL.Text:='select TELPATH from GLOB'; Open; s:=IncludeTrailingPathDelimiter(Trim(Fields[0].AsString));
      PathIn:=s+'входящие'+PathDelim;
      PathOut:=s+TelPathOut;
      FilePrm:=s+TelFilePrm;
      FileRead:=s+'прочитанные';
      Close;
      SelectSQL.Text:='select USERCNT from GLOBSET';
      Open; UserCnt:=Fields[0].AsInteger; UserNum:=UserCnt-1;
      Close;
      s:='RECNO+'+IntToStr(UserCnt-UserNum);
      SelectSQL.Text:=Format('select max(RECNO) from MSG where (cast ((%s)/%d as INTEGER))*%d=%s',
        [s,UserCnt,UserCnt,s]);
      Open; MsgRecno:=Fields[0].AsInteger;
      Close;
      SelectSQL.Text:='select R.RDB$FIELD_NAME,RDB$FIELD_TYPE,RDB$FIELD_LENGTH'
        +' from RDB$RELATION_FIELDS R, RDB$FIELDS F'
        +' where R.RDB$SYSTEM_FLAG = 0 and R.RDB$FIELD_SOURCE=F.RDB$FIELD_NAME'
        +' and R.RDB$RELATION_NAME="MSG"';
      Open; Last; i:=RecordCount; SetLength(aVal,i); First; j:=0;
      for i:=0 to i-1 do begin
        case Fields[1].AsInteger of
          blr_short,blr_long,blr_int64,blr_float,blr_double,blr_d_float: aVal[j]:='0';
          blr_timestamp,blr_sql_date,blr_sql_time,blr_blob,blr_blob_id: continue;
        else aVal[j]:='""';
        end;
        s:=Fields[0].AsString; lsFld.AddObject(s,pointer(j)); Inc(j);
        if s='TNFROM' then lMsgTn:=Fields[2].AsInteger;
        Next;
      end;
      lsFld.Sorted:=true; SetLength(aVal,j); sq:='';
      for j:=0 to j-1 do sq:=sq+','+lsFld[j];
      sq:='insert into MSG ('+Copy(sq,2,MaxInt)+') values (';
      SetVal('SEL','F');
      CntMsgTxt:=1;
      while lsFld.IndexOf(nmf254(CntMsgTxt))>=0 do Inc(CntMsgTxt);
      Dec(CntMsgTxt);
    finally
      Close; Free;
    end;
  end;
  GetStrFile(dFilePrm,FilePrm,lsPrm);
  //Опрашивает папку "входящие"
  i:=SysUtils.FindFirst(PathIn+'*.*',faAnyFile-faDirectory,sr);
  while i=0 do begin
    fn:=sr.Name;
    if fReadDel(PathIn+fn,txt) then begin
      //для каждого файла добавляет сообщение(RECNO как для UserNum=UserCnt-1), потом файл удаляет
      aSplitTxt254(PrSplitTxt254,[longint(Self)],txt,CntMsgTxt);
      Inc(MsgRecno,UserCnt);
      SetVal('RECNO',MsgRecno);
      j:=1;
      SetVal('TNFROM',SpaceStr(Part,lMsgTn));
      tnto:=SpaceStr(Part,lMsgTn); SetVal('TNTO',tnto);
      s:=Part; Delete(s,Length(s)-2,2); SetVal('TD',s);
      d1:=Now; td1:=DateToString(d1); SetVal('TD1',td1);
      s:=sq;
      for j:=0 to lsFld.Count-1 do s:=s+aVal[longint(lsFld.Objects[j])]+',';
      Upd(StuffString(s,Length(s),1,')'));
      //если в CDR.TEL ID отправителя определено и не отключен
      tnto:=Trim(tnto); s:=lsPrm.Values[tnto];
      if s<>'' then begin
        i:=Pos(',',s); fio:=LeftStr(s,i-1); j:=i+1;
        i:=PosEx(',',s,j); id:=Copy(s,j,i-j); j:=i+1;
        if Copy(s,j,MaxInt)<>'T' then TelMsgAdd(PathOut,MsgRecno,d1,td1,id,tnto+'.'+fio+CRLF+txt);
      end;
    end;
    i:=SysUtils.FindNext(sr);
  end;
  SysUtils.FindClose(sr);
  // для каждой строки файла "прочитанные" отмечать в Msg по Recno признак «Прочитано», удалить файл "прочитанные"
  if fReadDel(FileRead,s) then begin
    s:=TrimRight(s);
    if s<>'' then Upd('update MSG set SEL="T" where RECNO in ('+AnsiReplaceStr(s,CRLF,',')+') and SEL="F"');
  end;
end;

procedure TBot.SetVal(const nmf: string; const v: variant);
var s: string;
begin
  if TVarData(v).VType=varString then s:='"'+v+'"' else s:=IntToStr(v);
  aVal[longint(lsFld.Objects[lsFld.IndexOf(nmf)])]:=s;
end;

initialization
  Application.OnException:=TMain.ApplException;
finalization
  lsPrm.Free;
end.
