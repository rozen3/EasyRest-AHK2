#Requires AutoHotkey v2.0
#SingleInstance Force

; 版本号V2.12 (Multi-language Support)

; ==============================================================================
; 1. 初始化段与语言包
; ==============================================================================
Global pToken := 0, hCurrentIcon := 0
Global WorkTime := 1800000, RestDuration := 60, SnoozeTime := 300000, WindowTransparency := 255
Global MyGui := 0, RestGui := 0, CurrentCount := 0, IsPaused := false, IsResting := false, TimeElapsed := 0
Global ConfigFile := "config.ini"

; 语言包定义
Global Lang := Map()
Lang["zh"] := Map(
    "RestNow", "立即休息", "ThemeSet", "主题设置", "SetInterval", "设置提醒间隔",
    "SetTrans", "设置透明度", "Pause", "暂停提醒", "Resume", "恢复提醒", "Exit", "退出程序",
    "TransTitle", "调整透明度", "TransNote", "滑动调节窗口透明度 (0-100)", "Confirm", "确定",
    "RemindTitle", "✨ 休息时间到了", "RemindSub", "已经连续工作了 {1} 分钟`n建议您起身活动一下，缓解疲劳",
    "Snooze", "稍后再说", "Resting", "休息中", "Paused", "已暂停", "Remining", "剩余:",
    "SetTitle", "设置", "SetNote", "提醒间隔 (分钟):", "Min", "分", "LangSet", "Language / 语言"
)
Lang["en"] := Map(
    "RestNow", "Rest Now", "ThemeSet", "Theme Settings", "SetInterval", "Reminder Interval",
    "SetTrans", "Transparency", "Pause", "Pause", "Resume", "Resume", "Exit", "Exit",
    "TransTitle", "Adjust Transparency", "TransNote", "Adjust window transparency (0-100)", "Confirm", "OK",
    "RemindTitle", "✨ Time to Rest", "RemindSub", "You have been working for {1} minutes.`nTake a break to stay refreshed.",
    "Snooze", "Snooze", "Resting", "Resting", "Paused", "Paused", "Remining", "Left:",
    "SetTitle", "Settings", "SetNote", "Interval (Minutes):", "Min", "m", "LangSet", "Language / 语言"
)

; 自动检测或读取语言设置
Global CurrentLang := IniRead(ConfigFile, "Settings", "Language", (A_Language == "0804" ? "zh" : "en"))
Global L := Lang[CurrentLang]

; 主题配置
Global CurrentTheme := IniRead(ConfigFile, "Settings", "Theme", (CurrentLang == "zh" ? "简约白" : "Light"))
Global ThemeConfig := Map(
    "简约白", {Bg: "FFFFFF", Title: "1A1A1A", Sub: "666666", Btn: "0078D4", BtnT: "FFFFFF", Snooze: "E8E8E8", SnoozeT: "1A1A1A"},
    "Light", {Bg: "FFFFFF", Title: "1A1A1A", Sub: "666666", Btn: "0078D4", BtnT: "FFFFFF", Snooze: "E8E8E8", SnoozeT: "1A1A1A"},
    "极客黑", {Bg: "1E1E1E", Title: "FFFFFF", Sub: "AAAAAA", Btn: "3A3A3A", BtnT: "FFFFFF", Snooze: "2D2D2D", SnoozeT: "CCCCCC"},
    "Dark", {Bg: "1E1E1E", Title: "FFFFFF", Sub: "AAAAAA", Btn: "3A3A3A", BtnT: "FFFFFF", Snooze: "2D2D2D", SnoozeT: "CCCCCC"},
    "清新绿", {Bg: "F0F9F4", Title: "1E4620", Sub: "4A7C44", Btn: "2ECC71", BtnT: "FFFFFF", Snooze: "E2EFDE", SnoozeT: "1E4620"},
    "Green", {Bg: "F0F9F4", Title: "1E4620", Sub: "4A7C44", Btn: "2ECC71", BtnT: "FFFFFF", Snooze: "E2EFDE", SnoozeT: "1E4620"}
)

; 启动 GDI+
si := Buffer(24, 0), NumPut("UInt", 1, si)
DllCall("gdiplus\GdiplusStartup", "Ptr*", &pToken, "Ptr", si, "Ptr", 0)

; 加载配置
WorkTime := Integer(IniRead(ConfigFile, "Settings", "WorkTime", "1800000"))
WindowTransparency := Integer(IniRead(ConfigFile, "Settings", "Transparency", "255"))

; 系统监听
OnExit(Cleanup)
OnMessage(0x02B1, WM_WTSSESSION_CHANGE)
OnMessage(0x0201, WM_LBUTTONDOWN)
DllCall("wtsapi32.dll\WTSRegisterSessionNotification", "ptr", A_ScriptHwnd, "uint", 0)

; 构建托盘
InitTrayMenu()
UpdateDynamicTrayIcon("WORK", 0)
SetTimer(TickHandler, 1000)

; ==============================================================================
; 菜单初始化 (支持动态语言刷新)
; ==============================================================================

InitTrayMenu() {
    Global CurrentTheme, ThemeMenu, CurrentLang
    A_TrayMenu.Delete()
    A_TrayMenu.Add(L["RestNow"], (*) => StartForceRest())
    A_TrayMenu.Add()

    ThemeMenu := Menu()
    If (CurrentLang == "zh") {
        ThemeMenu.Add("简约白", SetTheme), ThemeMenu.Add("极客黑", SetTheme), ThemeMenu.Add("清新绿", SetTheme)
    } Else {
        ThemeMenu.Add("Light", SetTheme), ThemeMenu.Add("Dark", SetTheme), ThemeMenu.Add("Green", SetTheme)
    }
    Try ThemeMenu.Check(CurrentTheme)

    A_TrayMenu.Add(L["ThemeSet"], ThemeMenu)
    A_TrayMenu.Add(L["SetInterval"], SetWorkTime)
    A_TrayMenu.Add(L["SetTrans"], ShowTransSlider)

    ; 语言切换子菜单
    LangMenu := Menu()
    LangMenu.Add("简体中文", (*) => ChangeLanguage("zh"))
    LangMenu.Add("English", (*) => ChangeLanguage("en"))
    If (CurrentLang == "zh")
        LangMenu.Check("简体中文")
    Else
        LangMenu.Check("English")
    A_TrayMenu.Add(L["LangSet"], LangMenu)

    A_TrayMenu.Add(IsPaused ? L["Resume"] : L["Pause"], TogglePause)
    A_TrayMenu.Add()
    A_TrayMenu.Add(L["Exit"], (*) => ExitApp())
}

ChangeLanguage(LangCode) {
    Global CurrentLang := LangCode, L := Lang[LangCode], ConfigFile
    IniWrite(LangCode, ConfigFile, "Settings", "Language")
    Reload() ; 重新加载以应用所有UI变化
}

; ==============================================================================
; 2. 界面显示逻辑 (已应用语言包)
; ==============================================================================

ShowTransSlider(*) {
    Global WindowTransparency
    TransGui := Gui("+AlwaysOnTop", L["TransTitle"])
    TransGui.SetFont("s10 q5", "Segoe UI")
    TransGui.Add("Text", "Center w250", L["TransNote"])

    CurrentPercent := Round((WindowTransparency / 255) * 100)
    Sld := TransGui.Add("Slider", "w250 Range0-100 ToolTip", CurrentPercent)
    Sld.OnEvent("Change", (s, *) => UpdateTransLive(s.Value))

    BtnOk := TransGui.Add("Button", "Default w80 x85 y+15", L["Confirm"])
    BtnOk.OnEvent("Click", (g, *) => (TransGui.Hide(), TransGui.Destroy()))
    TransGui.OnEvent("Close", (g) => g.Destroy())
    TransGui.Show()
}

ShowModernReminder() {
    Global MyGui, CurrentTheme, ThemeConfig, WindowTransparency, WorkTime
    T := ThemeConfig[CurrentTheme]
    CurrentWorkMin := Round(WorkTime / 60000)

    MyGui := Gui("+AlwaysOnTop -Caption -Border +ToolWindow +E0x00080000")
    MyGui.BackColor := T.Bg
    WinSetTransparent(WindowTransparency, MyGui.Hwnd)

    MyGui.SetFont("s22 w600 q5", "Segoe UI")
    MyGui.Add("Text", "Center x0 y45 w460 c" T.Title, L["RemindTitle"])

    MyGui.SetFont("s11 w400 q5", "Segoe UI")
    MyGui.Add("Text", "Center x0 y105 w460 c" T.Sub, Format(L["RemindSub"], CurrentWorkMin))

    MyGui.SetFont("s12 w600 q5", "Segoe UI")
    BtnSnooze := MyGui.Add("Text", "x65 y185 w150 h48 +Center +0x201 c" T.SnoozeT " Background" T.Snooze, L["Snooze"])
    BtnSnooze.OnEvent("Click", (*) => CloseAndReset(Max(0, WorkTime - SnoozeTime)))

    BtnRest := MyGui.Add("Text", "x245 y185 w150 h48 +Center +0x201 c" T.BtnT " Background" T.Btn, L["RestNow"])
    BtnRest.OnEvent("Click", (*) => StartForceRest())

    ApplySmoothRoundedCorners(MyGui.Hwnd)
    MyGui.Show("w460 h280 x" IniRead(ConfigFile, "Position", "X", "Center") " y" IniRead(ConfigFile, "Position", "Y", "Center"))
}

UpdateDynamicTrayIcon(S, P) {
    Global hCurrentIcon, TimeElapsed, WorkTime
    hNew := CreateGdiIcon(S, P)
    Try TraySetIcon("HICON:" . hNew)
    if (hCurrentIcon != 0)
        DllCall("DestroyIcon", "Ptr", hCurrentIcon)
    hCurrentIcon := hNew
    A_IconTip := (S=="REST") ? L["Resting"] : (S=="PAUSE") ? L["Paused"] : L["Remining"] . Round((WorkTime-TimeElapsed)/60000, 1) . L["Min"]
}

; ... [保持 WM_LBUTTONDOWN, TickHandler, CreateGdiIcon, SetTheme, WM_WTSSESSION_CHANGE 等逻辑不变] ...

StartForceRest(*) {
    Global IsResting := true, CurrentCount := RestDuration, MyGui, RestGui
    if (MyGui != 0) {
        SaveWindowPos()
        MyGui.Destroy()
        MyGui := 0
    }
    UpdateDynamicTrayIcon("REST", 0)
    RestGui := Gui("+AlwaysOnTop -Caption -Border +ToolWindow")
    RestGui.BackColor := "000000"
    RestGui.SetFont("s150 w700 q5", "Segoe UI")
    RestGui.TimerText := RestGui.Add("Text", "Center x0 y" (A_ScreenHeight/2-110) " w" A_ScreenWidth " cFFFFFF", CurrentCount)
    RestGui.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
    BlockInput "Mouse"
    SetTimer(UpdateRestCountdown, 1000)
    HotKey("Esc", (*) => ExitForceRest(), "On")
}

UpdateRestCountdown() {
    Global CurrentCount -= 1
    if (CurrentCount <= 0)
        ExitForceRest()
    else
        Try RestGui.TimerText.Value := CurrentCount
}

ExitForceRest(*) {
    Global IsResting := false, TimeElapsed := 0, RestGui
    SetTimer(UpdateRestCountdown, 0)
    BlockInput "Off"
    HotKey("Esc", "Off")
    if (IsSet(RestGui) && RestGui) {
        RestGui.Destroy()
        RestGui := 0
    }
    UpdateDynamicTrayIcon("WORK", 0)
}

Cleanup(*) {
    Global hCurrentIcon
    SetTimer(TickHandler, 0)
    SetTimer(UpdateRestCountdown, 0)
    A_IconHidden := true
    if (hCurrentIcon != 0) {
        DllCall("DestroyIcon", "Ptr", hCurrentIcon)
        hCurrentIcon := 0
    }
}

TogglePause(*) {
    Global IsPaused := !IsPaused, TimeElapsed, WorkTime
    InitTrayMenu() ; 刷新菜单文本
    UpdateDynamicTrayIcon(IsPaused ? "PAUSE" : "WORK", TimeElapsed / WorkTime)
}

CloseAndReset(v) {
    Global TimeElapsed := v, MyGui, WorkTime
    if (MyGui != 0) {
        SaveWindowPos()
        MyGui.Destroy()
        MyGui := 0
    }
    UpdateDynamicTrayIcon("WORK", TimeElapsed / WorkTime)
}

SetWorkTime(*) {
    ib := InputBox(L["SetNote"], L["SetTitle"], , Round(WorkTime/60000, 1))
    if (ib.Result == "OK") {
        Global WorkTime := Round(Float(ib.Value)*60000), TimeElapsed := 0
        IniWrite(WorkTime, ConfigFile, "Settings", "WorkTime")
        UpdateDynamicTrayIcon("WORK", 0)
    }
}

UpdateTransLive(Percent) {
    Global WindowTransparency := Round((Percent / 100) * 255), MyGui, ConfigFile
    IniWrite(WindowTransparency, ConfigFile, "Settings", "Transparency")
    if (IsSet(MyGui) && MyGui) {
        WinSetTransparent(WindowTransparency, MyGui.Hwnd)
    }
}

WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    Global MyGui
    if (IsSet(MyGui) && MyGui && hwnd == MyGui.Hwnd) {
        PostMessage(0xA1, 2, 0, , "ahk_id " MyGui.Hwnd)
    }
}

TickHandler() {
    Global TimeElapsed, MyGui, IsResting, IsPaused, WorkTime
    if (IsResting || IsPaused) {
        UpdateDynamicTrayIcon(IsResting ? "REST" : "PAUSE", 0)
        return
    }
    TimeElapsed += 1000
    UpdateDynamicTrayIcon("WORK", Min(1.0, TimeElapsed / WorkTime))
    if (TimeElapsed >= WorkTime && MyGui == 0)
        ShowModernReminder()
}

CreateGdiIcon(State, Progress) {
    Static Size := 32
    pBitmap := 0, G := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", Size, "Int", Size, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBitmap)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pBitmap, "Ptr*", &G)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", G, "Int", 4)
    if (State == "WORK") {
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFF0F0F0, "Ptr*", &pB1 := 0)
        DllCall("gdiplus\GdipFillEllipse", "Ptr", G, "Ptr", pB1, "Float", 1, "Float", 1, "Float", 30, "Float", 30)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", pB1)
        c := (Progress < 0.9) ? 0xFF2ECC71 : 0xFFE74C3C
        DllCall("gdiplus\GdipCreatePen1", "UInt", c, "Float", 7, "Int", 2, "Ptr*", &pP := 0)
        DllCall("gdiplus\GdipDrawArc", "Ptr", G, "Ptr", pP, "Float", 4.5, "Float", 4.5, "Float", 23, "Float", 23, "Float", -90, "Float", Progress * 360)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pP)
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFFFFFFF, "Ptr*", &pB2 := 0)
        DllCall("gdiplus\GdipFillEllipse", "Ptr", G, "Ptr", pB2, "Float", 10, "Float", 10, "Float", 12, "Float", 12)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", pB2)
    } else {
        color := (State == "PAUSE") ? 0xFFB0BEC5 : 0xFF2ECC71
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", color, "Ptr*", &pB3 := 0)
        DllCall("gdiplus\GdipFillEllipse", "Ptr", G, "Ptr", pB3, "Float", 2, "Float", 2, "Float", 28, "Float", 28)
        DllCall("gdiplus\GdipDeleteBrush", "Ptr", pB3)
        if (State == "PAUSE") {
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFFFFFFF, "Ptr*", &pB4 := 0)
            DllCall("gdiplus\GdipFillRectangle", "Ptr", G, "Ptr", pB4, "Float", 11, "Float", 10, "Float", 3, "Float", 12)
            DllCall("gdiplus\GdipFillRectangle", "Ptr", G, "Ptr", pB4, "Float", 18, "Float", 10, "Float", 3, "Float", 12)
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", pB4)
        }
    }
    hIcon := 0
    DllCall("gdiplus\GdipCreateHICONFromBitmap", "Ptr", pBitmap, "Ptr*", &hIcon)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", G)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
    return hIcon
}

SetTheme(ThemeName, *) {
    Global CurrentTheme, ConfigFile, ThemeMenu
    Try ThemeMenu.Uncheck(CurrentTheme)
    CurrentTheme := ThemeName
    ThemeMenu.Check(CurrentTheme)
    IniWrite(CurrentTheme, ConfigFile, "Settings", "Theme")
    if (IsSet(MyGui) && MyGui) {
        SaveWindowPos()
        MyGui.Destroy()
        ShowModernReminder()
    }
}

WM_WTSSESSION_CHANGE(wp, lp, msg, hwnd) {
    if (wp == 7) {
        Global IsPaused := true
        UpdateDynamicTrayIcon("PAUSE", 0)
    } else if (wp == 8) {
        Global IsPaused := false
    }
}

ApplySmoothRoundedCorners(h) {
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", h, "int", 33, "int*", 2, "int", 4)
}

SaveWindowPos() {
    Global MyGui, ConfigFile
    if (MyGui != 0) {
        WinGetPos(&px, &py, , , MyGui.Hwnd)
        IniWrite(px, ConfigFile, "Position", "X")
        IniWrite(py, ConfigFile, "Position", "Y")
    }
}
