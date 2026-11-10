#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
#UseHook

; ============================================================
; 双屏焦点 v6.9 · 哔哩选片页可上主屏，播放页只留副屏
; 主屏：普通窗铺满；微信/QQ/企微 → 工作区居中大浮窗（约 90%）
; 副屏：对话/AI + 哔哩播放页（只留副屏，禁止扩展到主屏；单窗占上半）
; 哔哩选片/首页：选中时上主屏，不钉死在副屏
;   文件夹 → 可开关关闭；Word/PPT/PDF 等 → 最小化
; 配置：脚本同目录 FocusMain.ini
; ============================================================

SetWinDelay -1
SetControlDelay -1

ConfigPath := A_ScriptDir "\FocusMain.ini"

; ----- 可配置项（默认值，启动时被 ini 覆盖）-----
Enabled := true
SecondarySlots := 4
CloseFolders := true
ChatMainRatioW := 0.58  ; 主屏聊天窗宽度占工作区比例
ChatMainRatioH := 0.78  ; 高度比例（按用户微调参考图）
ChatMainRatio := 0.58   ; 兼容旧 ini 的单一比例

layoutBusy := false
busySince := 0
altStartHwnd := 0
altArmed := false
settingsGui := 0

mainL := 0, mainT := 0, mainW := 0, mainH := 0
secL := 0, secT := 0, secW := 0, secH := 0
hasDual := false

ExcludeClasses := Map(
    "Progman", 1, "WorkerW", 1,
    "Shell_TrayWnd", 1, "Shell_SecondaryTrayWnd", 1,
    "DV2ControlHost", 1, "Windows.UI.Core.CoreWindow", 1,
    "AutoHotkeyGUI", 1
)

; 默认副屏白名单：进程名（小写）
DefaultKeepExeList := [
    "wechat.exe",
    "weixin.exe",
    "wxwork.exe",
    "qq.exe",
    "qqnt.exe",
    "tim.exe",
    "chatgpt.exe",
    "claude.exe",
    "cursor.exe",
    "grok.exe",
    "copilot.exe",
    "doubao.exe",
    "yuanbao.exe",
    "kimi.exe",
    "sidekick.exe",
    "哔哩哔哩.exe",
    "bilibili.exe",
    "bili.exe"
]

; 主屏用「大窗居中」而非铺满的聊天类进程
ChatMainExe := Map(
    "wechat.exe", 1,
    "weixin.exe", 1,
    "wxwork.exe", 1,
    "qq.exe", 1,
    "qqnt.exe", 1,
    "tim.exe", 1
)

; 固定放副屏（即使当前是前台窗也不上主屏）
SidePreferExe := Map(
    "哔哩哔哩.exe", 1,
    "bilibili.exe", 1,
    "bili.exe", 1
)

; 默认标题关键词
DefaultKeepTitleNeedles := [
    "微信", "WeChat", "Weixin", "企业微信",
    "QQ", "TIM",
    "ChatGPT", "Claude", "Grok", "Gemini", "Copilot",
    "豆包", "元宝", "Kimi", "通义", "文心", "智谱", "POE", "Poe",
    "Grok Bot",
    "哔哩哔哩", "bilibili", "Bilibili"
]

KeepExe := Map()
KeepTitleNeedles := []

; 直接关闭：资源管理器文件夹
CloseExe := Map("explorer.exe", 1)
CloseClasses := Map("CabinetWClass", 1, "ExploreWClass", 1)

; 最小化：文档类
MinExe := Map(
    "winword.exe", 1,
    "powerpnt.exe", 1,
    "excel.exe", 1,
    "wps.exe", 1,
    "wpp.exe", 1,
    "et.exe", 1,
    "acrord32.exe", 1,
    "acrobat.exe", 1,
    "mspaint.exe", 1,
    "notepad.exe", 1,
    "notepad++.exe", 1
)

ApplyDefaultWhitelist() {
    global KeepExe, KeepTitleNeedles, DefaultKeepExeList, DefaultKeepTitleNeedles
    KeepExe := Map()
    for exe in DefaultKeepExeList
        KeepExe[exe] := 1
    KeepTitleNeedles := []
    for t in DefaultKeepTitleNeedles
        KeepTitleNeedles.Push(t)
}

ExeMapToText(m) {
    lines := []
    for k, _ in m
        lines.Push(k)
    return JoinLines(lines)
}

TitleArrToText(arr) {
    return JoinLines(arr)
}

JoinLines(arr) {
    out := ""
    for i, v in arr {
        if (i > 1)
            out .= "`n"
        out .= v
    }
    return out
}

ParseExeText(text) {
    m := Map()
    for line in StrSplit(text, "`n", "`r") {
        s := Trim(line)
        if (s = "" || SubStr(s, 1, 1) = ";")
            continue
        s := StrLower(s)
        if !InStr(s, ".")
            s .= ".exe"
        m[s] := 1
    }
    return m
}

ParseTitleText(text) {
    arr := []
    for line in StrSplit(text, "`n", "`r") {
        s := Trim(line)
        if (s = "" || SubStr(s, 1, 1) = ";")
            continue
        arr.Push(s)
    }
    return arr
}

LoadConfig() {
    global ConfigPath, Enabled, SecondarySlots, CloseFolders, ChatMainRatio, ChatMainRatioW, ChatMainRatioH, KeepExe, KeepTitleNeedles, ChatMainExe, SidePreferExe
    ApplyDefaultWhitelist()
    if !FileExist(ConfigPath)
        return
    Enabled := (IniRead(ConfigPath, "Settings", "Enabled", "1") = "1")
    SecondarySlots := Integer(IniRead(ConfigPath, "Settings", "SecondarySlots", "4"))
    if (SecondarySlots < 2 || SecondarySlots > 4)
        SecondarySlots := 4
    CloseFolders := (IniRead(ConfigPath, "Settings", "CloseFolders", "1") = "1")
    try ChatMainRatio := Float(IniRead(ConfigPath, "Settings", "ChatMainRatio", "0.58"))
    if (ChatMainRatio < 0.5 || ChatMainRatio > 0.98)
        ChatMainRatio := 0.58
    try ChatMainRatioW := Float(IniRead(ConfigPath, "Settings", "ChatMainRatioW", ChatMainRatio))
    try ChatMainRatioH := Float(IniRead(ConfigPath, "Settings", "ChatMainRatioH", "0.78"))
    if (ChatMainRatioW < 0.5 || ChatMainRatioW > 0.98)
        ChatMainRatioW := 0.58
    if (ChatMainRatioH < 0.5 || ChatMainRatioH > 0.98)
        ChatMainRatioH := 0.78
    exeText := IniRead(ConfigPath, "Whitelist", "ExeList", "")
    titleText := IniRead(ConfigPath, "Whitelist", "TitleList", "")
    if (exeText != "" && exeText != "ERROR") {
        ; ini 里用 | 分隔
        KeepExe := Map()
        for part in StrSplit(exeText, "|") {
            s := StrLower(Trim(part))
            if (s != "")
                KeepExe[s] := 1
        }
    }
    if (titleText != "" && titleText != "ERROR") {
        KeepTitleNeedles := []
        for part in StrSplit(titleText, "|") {
            s := Trim(part)
            if (s != "")
                KeepTitleNeedles.Push(s)
        }
    }
    ; 保证聊天类进程在白名单里（旧 ini 可能缺 qq）
    for exe, _ in ChatMainExe
        KeepExe[exe] := 1
    ; 哔哩哔哩等固定副屏进程也写入白名单（旧 ini 可能没有）
    for exe, _ in SidePreferExe
        KeepExe[exe] := 1
}

SaveConfig() {
    global ConfigPath, Enabled, SecondarySlots, CloseFolders, ChatMainRatio, ChatMainRatioW, ChatMainRatioH, KeepExe, KeepTitleNeedles
    IniWrite(Enabled ? "1" : "0", ConfigPath, "Settings", "Enabled")
    IniWrite(SecondarySlots, ConfigPath, "Settings", "SecondarySlots")
    IniWrite(CloseFolders ? "1" : "0", ConfigPath, "Settings", "CloseFolders")
    IniWrite(ChatMainRatioW, ConfigPath, "Settings", "ChatMainRatio")
    IniWrite(ChatMainRatioW, ConfigPath, "Settings", "ChatMainRatioW")
    IniWrite(ChatMainRatioH, ConfigPath, "Settings", "ChatMainRatioH")
    exeParts := []
    for k, _ in KeepExe
        exeParts.Push(k)
    titleParts := []
    for t in KeepTitleNeedles
        titleParts.Push(t)
    IniWrite(JoinPipe(exeParts), ConfigPath, "Whitelist", "ExeList")
    IniWrite(JoinPipe(titleParts), ConfigPath, "Whitelist", "TitleList")
}

JoinPipe(arr) {
    out := ""
    for i, v in arr {
        if (i > 1)
            out .= "|"
        out .= v
    }
    return out
}

UpdateTrayTip() {
    global Enabled, SecondarySlots, CloseFolders
    state := Enabled ? "已启用" : "已暂停"
    tip := "双屏焦点 v6.9 · " state "`n微信/QQ 上主屏居中大窗；副屏 " SecondarySlots " 格；文件夹" (CloseFolders ? "关闭" : "最小化")
    A_IconTip := tip
}

LoadConfig()
UpdateTrayTip()

RefreshMonitors(*) {
    global mainL, mainT, mainW, mainH, secL, secT, secW, secH, hasDual
    count := MonitorGetCount()
    hasDual := false
    if (count < 1)
        return
    best := 1, bestArea := 0
    Loop count {
        MonitorGetWorkArea(A_Index, &L, &T, &R, &B)
        a := (R - L) * (B - T)
        if (a > bestArea) {
            bestArea := a
            best := A_Index
        }
    }
    MonitorGetWorkArea(best, &L, &T, &R, &B)
    mainL := L, mainT := T, mainW := R - L, mainH := B - T
    if (count < 2)
        return
    Loop count {
        if (A_Index = best)
            continue
        MonitorGetWorkArea(A_Index, &L, &T, &R, &B)
        secL := L, secT := T, secW := R - L, secH := B - T
        hasDual := true
        break
    }
}
RefreshMonitors()
OnMessage(0x007E, RefreshMonitors)

IsUsable(hwnd) {
    if !hwnd || !DllCall("IsWindowVisible", "ptr", hwnd)
        return false
    try {
        if (WinGetExStyle(hwnd) & 0x80)
            return false
        t := WinGetTitle(hwnd)
        if (t = "" || t = "Program Manager")
            return false
        c := WinGetClass(hwnd)
        if ExcludeClasses.Has(c) && ExcludeClasses[c]
            return false
        return true
    } catch {
        return false
    }
}

GetExe(hwnd) {
    try {
        return StrLower(WinGetProcessName(hwnd))
    } catch {
        return ""
    }
}

IsBiliHomeTitle(title) {
    if (title = "")
        return false
    if InStr(title, "干杯") || InStr(title, "゜-゜")
        return true
    t := Trim(title)
    if (t = "哔哩哔哩" || StrLower(t) = "bilibili")
        return true
    if InStr(title, "哔哩哔哩") && InStr(StrLower(title), "-bilibili")
        return true
    return false
}

; 选片/首页主窗：允许 Alt+Tab / Alt+` 提到主屏
IsBiliBrowseWindow(hwnd) {
    if !hwnd
        return false
    exe := GetExe(hwnd)
    if !IsSidePreferExeName(exe) {
        try {
            owner := DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")
            if (owner && owner != hwnd && IsSidePreferExeName(GetExe(owner)))
                exe := GetExe(owner)
        }
        if !IsSidePreferExeName(exe) {
            try {
                root := DllCall("GetAncestor", "ptr", hwnd, "uint", 3, "ptr")
                if (root && root != hwnd && IsSidePreferExeName(GetExe(root)))
                    exe := GetExe(root)
            }
        }
    }
    if !IsSidePreferExeName(exe)
        return false
    try {
        return IsBiliHomeTitle(WinGetTitle("ahk_id " hwnd))
    } catch {
        return false
    }
}

IsSidePrefer(hwnd) {
    global SidePreferExe
    if !hwnd
        return false
    ; 选片页不是「固定副屏」，选中时可上主屏
    if IsBiliBrowseWindow(hwnd)
        return false
    if IsSidePreferExeName(GetExe(hwnd))
        return true
    try {
        title := WinGetTitle("ahk_id " hwnd)
        for needle in ["哔哩哔哩", "bilibili", "Bilibili"] {
            if InStr(title, needle)
                return true
        }
    }
    ; 播放器/WebView 可能是子进程顶层窗，沿 owner 根窗口判断
    try {
        owner := DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")
        if (owner && owner != hwnd && IsSidePreferExeName(GetExe(owner)))
            return true
    }
    try {
        root := DllCall("GetAncestor", "ptr", hwnd, "uint", 3, "ptr")
        if (root && root != hwnd && IsSidePreferExeName(GetExe(root)))
            return true
    }
    return false
}

IsSidePreferExeName(exe) {
    global SidePreferExe
    return (exe != "" && SidePreferExe.Has(exe))
}

WindowRect(hwnd, &x, &y, &w, &h) {
    x := 0, y := 0, w := 0, h := 0
    try WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
}

IntersectsMain(hwnd) {
    global mainL, mainT, mainW, mainH
    WindowRect(hwnd, &x, &y, &w, &h)
    if (w < 1 || h < 1 || (x <= -32000 && y <= -32000))
        return false
    return (x < mainL + mainW && x + w > mainL && y < mainT + mainH && y + h > mainT)
}

IsMostlyOnSecondary(hwnd) {
    global secL, secT, secW, secH
    WindowRect(hwnd, &x, &y, &w, &h)
    if (w < 1 || h < 1 || (x <= -32000 && y <= -32000))
        return false
    cx := x + w // 2, cy := y + h // 2
    return (cx >= secL && cx < secL + secW && cy >= secT && cy < secT + secH)
}

LooksFullscreen(hwnd) {
    global mainW, mainH, secW, secH
    try {
        if WinGetMinMax("ahk_id " hwnd) = 1
            return true
    }
    WindowRect(hwnd, &x, &y, &w, &h)
    if (w >= mainW * 0.9 && h >= mainH * 0.9)
        return true
    if (w >= secW * 0.9 && h >= secH * 0.9)
        return true
    return false
}

CollectSideForPrefer(focusHwnd, limit) {
    side := []
    if focusHwnd
        side.Push(focusHwnd)
    for hwnd in WinGetList() {
        if (hwnd = focusHwnd)
            continue
        if !DllCall("IsWindowVisible", "ptr", hwnd)
            continue
        isMin := false
        try {
            isMin := (WinGetMinMax("ahk_id " hwnd) = -1)
        }
        if isMin {
            if !IsSidePrefer(hwnd)
                continue
            try WinRestore("ahk_id " hwnd)
        }
        if IsSidePrefer(hwnd) {
            if (side.Length < limit)
                side.Push(hwnd)
            continue
        }
        if !IsUsable(hwnd)
            continue
        if IsKeepSide(hwnd) && IsMostlyOnSecondary(hwnd) {
            if (side.Length < limit)
                side.Push(hwnd)
        }
    }
    return side
}

ClampSidePreferOffMain() {
    global hasDual, secL, secT, secW, secH
    if !hasDual
        return
    for hwnd in WinGetList() {
        if !IsSidePrefer(hwnd)
            continue
        if !DllCall("IsWindowVisible", "ptr", hwnd)
            continue
        try {
            if WinGetMinMax("ahk_id " hwnd) = -1
                continue
        }
        wasFs := LooksFullscreen(hwnd)
        if !IntersectsMain(hwnd) && !wasFs
            continue
        try {
            if WinGetMinMax("ahk_id " hwnd) != 0
                WinRestore("ahk_id " hwnd)
        }
        if wasFs {
            MoveSide(hwnd, secL, secT, secW, secH)
            continue
        }
        WindowRect(hwnd, &x, &y, &w, &h)
        nw := Min(Max(w, 200), secW)
        nh := Min(Max(h, 200), secH)
        ny := (y + h // 2 > secT + secH // 2) ? (secT + secH - nh) : secT
        MoveSide(hwnd, secL, ny, nw, nh)
    }
}

ScheduleClampOffMain() {
    SetTimer(ClampPass1, -250)
}

ClampPass1() {
    ClampSidePreferOffMain()
    SetTimer(ClampSidePreferOffMain, -450)
}

EnsureFirst(hwnd, arr) {
    out := [hwnd]
    for h in arr {
        if (h != hwnd)
            out.Push(h)
    }
    return out
}

IsKeepSide(hwnd) {
    global KeepExe, KeepTitleNeedles
    if IsSidePrefer(hwnd)
        return true
    exe := GetExe(hwnd)
    if (exe != "" && KeepExe.Has(exe))
        return true
    try {
        title := WinGetTitle(hwnd)
    } catch {
        return false
    }
    for needle in KeepTitleNeedles {
        if InStr(title, needle)
            return true
    }
    ; 浏览器里开着 AI 页（代码内默认，不进设置）
    if (exe = "chrome.exe" || exe = "msedge.exe" || exe = "firefox.exe" || exe = "brave.exe") {
        for needle in ["ChatGPT", "claude.ai", "gemini.google", "copilot", "Grok", "豆包", "kimi", "哔哩哔哩", "bilibili"] {
            if InStr(title, needle)
                return true
        }
    }
    return false
}

IsFolderWindow(hwnd) {
    global CloseExe, CloseClasses
    try {
        cls := WinGetClass(hwnd)
        if CloseClasses.Has(cls)
            return true
    }
    exe := GetExe(hwnd)
    if (exe = "explorer.exe") {
        try {
            if WinGetClass(hwnd) = "CabinetWClass"
                return true
        }
    }
    return false
}

IsDocWindow(hwnd) {
    global MinExe
    exe := GetExe(hwnd)
    return (exe != "" && MinExe.Has(exe))
}

IsChatMainWindow(hwnd) {
    global ChatMainExe
    exe := GetExe(hwnd)
    return (exe != "" && ChatMainExe.Has(exe))
}

ForceToMain(hwnd) {
    global mainL, mainT, mainW, mainH
    if !hwnd || !WinExist(hwnd)
        return
    try {
        if WinGetMinMax(hwnd) != 0
            WinRestore(hwnd)
    }
    try WinMove(mainL, mainT, mainW, mainH, hwnd)
    try WinActivate(hwnd)
}

; 取 Win11 隐形边框，使「看得见的」客户区相对工作区真正居中
GetDwmMargins(hwnd, &ml, &mt, &mr, &mb) {
    ml := 0, mt := 0, mr := 0, mb := 0
    winRect := Buffer(16), frame := Buffer(16)
    if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", winRect)
        return
    ; DWMWA_EXTENDED_FRAME_BOUNDS = 9
    if DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "int", 9, "ptr", frame, "uint", 16)
        return
    wrL := NumGet(winRect, 0, "int"), wrT := NumGet(winRect, 4, "int")
    wrR := NumGet(winRect, 8, "int"), wrB := NumGet(winRect, 12, "int")
    frL := NumGet(frame, 0, "int"), frT := NumGet(frame, 4, "int")
    frR := NumGet(frame, 8, "int"), frB := NumGet(frame, 12, "int")
    ml := frL - wrL
    mt := frT - wrT
    mr := wrR - frR
    mb := wrB - frB
}

; 微信/QQ/企微：相对主屏工作区真正居中的大浮窗（不铺满）
PlaceChatOnMain(hwnd) {
    global mainL, mainT, mainW, mainH, ChatMainRatioW, ChatMainRatioH
    if !hwnd || !WinExist(hwnd)
        return
    RefreshMonitors()
    try {
        if WinGetMinMax(hwnd) != 0
            WinRestore(hwnd)
    }
    Sleep 30
    rw := ChatMainRatioW, rh := ChatMainRatioH
    if (rw < 0.5 || rw > 0.98)
        rw := 0.58
    if (rh < 0.5 || rh > 0.98)
        rh := 0.78
    ; 目标：看得见的外框居中于主屏工作区
    visW := Integer(mainW * rw)
    visH := Integer(mainH * rh)
    visX := mainL + (mainW - visW) // 2
    visY := mainT + (mainH - visH) // 2
    GetDwmMargins(hwnd, &ml, &mt, &mr, &mb)
    ; WinMove 用的是含隐形边框的外接矩形，需向外扩边距
    x := visX - ml
    y := visY - mt
    w := visW + ml + mr
    h := visH + mt + mb
    try WinMove(x, y, w, h, "ahk_id " hwnd)
    ; 微信常限制最大宽度：按实际可见尺寸再居中一次，避免贴左
    Sleep 40
    GetDwmMargins(hwnd, &ml2, &mt2, &mr2, &mb2)
    try {
        WinGetPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
        curVisW := Max(100, cw - ml2 - mr2)
        curVisH := Max(100, ch - mt2 - mb2)
        ; 若明显小于目标宽，保留实际大小，只纠正居中
        useW := (curVisW < visW - 20) ? curVisW : visW
        useH := (curVisH < visH - 20) ? curVisH : visH
        visX2 := mainL + (mainW - useW) // 2
        visY2 := mainT + (mainH - useH) // 2
        x2 := visX2 - ml2
        y2 := visY2 - mt2
        w2 := useW + ml2 + mr2
        h2 := useH + mt2 + mb2
        WinMove(x2, y2, w2, h2, "ahk_id " hwnd)
    }
    try WinActivate("ahk_id " hwnd)
}

PlaceOnMain(hwnd) {
    if IsChatMainWindow(hwnd)
        PlaceChatOnMain(hwnd)
    else
        ForceToMain(hwnd)
}

MoveSide(hwnd, x, y, w, h) {
    if !hwnd || !WinExist(hwnd)
        return
    try {
        if WinGetMinMax("ahk_id " hwnd) != 0
            WinRestore("ahk_id " hwnd)
    }
    try WinMove(x, y, w, h, "ahk_id " hwnd)
}

SnapSide(hwnds) {
    global secL, secT, secW, secH
    n := Min(hwnds.Length, 4)
    if (n <= 0)
        return
    L := secL, T := secT, W := secW, H := secH
    if (n = 1) {
        ; 只有一个窗口时占副屏上半，不铺满
        MoveSide(hwnds[1], L, T, W, H // 2)
        return
    }
    if (n = 2) {
        h1 := H // 2
        MoveSide(hwnds[1], L, T, W, h1)
        MoveSide(hwnds[2], L, T + h1, W, H - h1)
        return
    }
    if (n = 3) {
        h1 := H // 3
        h2 := H // 3
        MoveSide(hwnds[1], L, T, W, h1)
        MoveSide(hwnds[2], L, T + h1, W, h2)
        MoveSide(hwnds[3], L, T + h1 + h2, W, H - h1 - h2)
        return
    }
    hw := W // 2
    hh := H // 2
    MoveSide(hwnds[1], L, T, hw, hh)
    MoveSide(hwnds[2], L + hw, T, W - hw, hh)
    MoveSide(hwnds[3], L, T + hh, hw, H - hh)
    MoveSide(hwnds[4], L + hw, T + hh, W - hw, H - hh)
}

; 分类处理：收集副屏候选，同时关掉文件夹、最小化文档/杂项
CollectSideAndCleanup(excludeHwnd, limit) {
    global CloseFolders
    side := []
    for hwnd in WinGetList() {
        if (hwnd = excludeHwnd || !IsUsable(hwnd))
            continue
        isMin := false
        try {
            isMin := (WinGetMinMax(hwnd) = -1)
        }
        if isMin {
            ; 哔哩哔哩等固定副屏窗：被上次误最小化的，拉回来
            if !IsSidePrefer(hwnd)
                continue
            try WinRestore(hwnd)
        }

        if IsFolderWindow(hwnd) {
            if CloseFolders {
                try WinClose(hwnd)
            } else {
                try WinMinimize(hwnd)
            }
            continue
        }
        if IsKeepSide(hwnd) {
            if (side.Length < limit)
                side.Push(hwnd)
            continue
        }
        if IsDocWindow(hwnd) {
            try WinMinimize(hwnd)
            continue
        }
        try WinMinimize(hwnd)
    }
    return side
}

DoLayout(hwnd := 0) {
    global layoutBusy, busySince, hasDual, SecondarySlots, Enabled
    if !Enabled
        return
    if layoutBusy {
        if (A_TickCount - busySince < 2000)
            return
        layoutBusy := false
    }
    if !hwnd
        hwnd := WinExist("A")
    if !hwnd
        return
    preferSide := IsSidePrefer(hwnd)
    if !preferSide && !IsUsable(hwnd)
        return

    layoutBusy := true
    busySince := A_TickCount
    try {
        if !preferSide
            PlaceOnMain(hwnd)
        if hasDual {
            if preferSide {
                ; 选中哔哩只钉副屏：不把主屏上的 ChatGPT 等拉下来，也不让它铺到主屏
                side := CollectSideForPrefer(hwnd, SecondarySlots)
                side := EnsureFirst(hwnd, side)
                SnapSide(side)
                ClampSidePreferOffMain()
                ScheduleClampOffMain()
            } else {
                side := CollectSideAndCleanup(hwnd, SecondarySlots)
                SnapSide(side)
                ClampSidePreferOffMain()
            }
        }
        try WinActivate("ahk_id " hwnd)
    } catch {
        TrayTip("双屏焦点", "排布失败，再按 Alt+``", "Icon!")
        SetTimer(() => TrayTip(), -2000)
    } finally {
        layoutBusy := false
    }
}

~LAlt:: {
    global altStartHwnd, altArmed
    altStartHwnd := WinExist("A")
    altArmed := true
}
~RAlt:: {
    global altStartHwnd, altArmed
    altStartHwnd := WinExist("A")
    altArmed := true
}
OnAltUp(*) {
    global altArmed
    if !altArmed
        return
    altArmed := false
    SetTimer(AfterAltTab, -60)
}
~LAlt Up:: OnAltUp()
~RAlt Up:: OnAltUp()

AfterAltTab(*) {
    global altStartHwnd
    now := WinExist("A")
    if !now || !IsUsable(now)
        return
    if (altStartHwnd && now != altStartHwnd)
        DoLayout(now)
}

!`:: DoLayout(WinExist("A"))
^!`:: DoLayout(WinExist("A"))

ForceLayout(*) {
    DoLayout(WinExist("A"))
}

;; ========== 滑动开关（自绘）==========
PaintToggle(ctrl, isOn) {
    if isOn {
        ctrl.Opt("Background0078D4 cWhite")
        ctrl.Value := "开　●"
    } else {
        ctrl.Opt("BackgroundB0B0B0 cWhite")
        ctrl.Value := "●　关"
    }
}

; ========== 设置 GUI ==========
OpenSettings(*) {
    global settingsGui, Enabled, SecondarySlots, CloseFolders, KeepExe, KeepTitleNeedles
    if settingsGui {
        try {
            settingsGui.Show()
            WinActivate("ahk_id " settingsGui.Hwnd)
            return
        } catch {
            settingsGui := 0
        }
    }

    ; 窗口内临时状态（对象属性，嵌套回调可稳定读写）
    ui := {Enabled: Enabled, CloseFolders: CloseFolders, Slots: SecondarySlots}

    g := Gui("+AlwaysOnTop -MinimizeBox", "双屏焦点 · 设置")
    g.BackColor := "F7F8FA"
    g.SetFont("s9 c666666", "Microsoft YaHei UI")
    g.MarginX := 20
    g.MarginY := 16

    g.AddText("xm", "总开关与布局")
    g.AddText("xm y+2 w420 h1 BackgroundE0E0E0", "")

    ; —— 启用双屏焦点 ——
    g.SetFont("s10 c222222", "Microsoft YaHei UI")
    g.AddText("xm y+14 w330 Section", "启用双屏焦点")
    g.SetFont("s8 c888888", "Microsoft YaHei UI")
    g.AddText("xm y+2 w330", "关闭后热键仍在，但不会自动排布窗口")
    g.SetFont("s10 Bold cWhite", "Microsoft YaHei UI")
    togEn := g.AddText("ys x+8 w58 h28 Center 0x200 +0x100", "")
    PaintToggle(togEn, ui.Enabled)
    togEn.OnEvent("Click", ToggleEnabled)

    ; —— 分屏样式 ——
    g.SetFont("s10 c222222", "Microsoft YaHei UI")
    g.AddText("xm y+18 w120 Section", "分屏样式")
    g.SetFont("s10 Norm c222222", "Microsoft YaHei UI")
    ddSlots := g.AddDropDownList("vSlots ys w200 Choose" (ui.Slots - 1), ["2 上下", "3 上中下", "4 四宫格"])
    ddSlots.Choose(ui.Slots - 1)

    ; —— 关闭文件夹 ——
    g.SetFont("s10 c222222", "Microsoft YaHei UI")
    g.AddText("xm y+18 w330 Section", "关闭文件夹")
    g.SetFont("s8 c888888", "Microsoft YaHei UI")
    g.AddText("xm y+2 w330", "关闭后文件夹改为最小化，不再直接关掉")
    g.SetFont("s10 Bold cWhite", "Microsoft YaHei UI")
    togFolder := g.AddText("ys x+8 w58 h28 Center 0x200 +0x100", "")
    PaintToggle(togFolder, ui.CloseFolders)
    togFolder.OnEvent("Click", ToggleFolders)

    ; —— 白名单 ——
    g.SetFont("s9 c666666", "Microsoft YaHei UI")
    g.AddText("xm y+22", "副屏白名单")
    g.AddText("xm y+2 w420 h1 BackgroundE0E0E0", "")

    g.SetFont("s9 c444444", "Microsoft YaHei UI")
    g.AddText("xm y+12", "进程名（每行一个 .exe）")
    g.SetFont("s9 c222222", "Consolas")
    editExe := g.AddEdit("vExeList Multi WantReturn w420 r7 BackgroundWhite", ExeMapToText(KeepExe))

    g.SetFont("s9 c444444", "Microsoft YaHei UI")
    g.AddText("xm y+12", "标题关键词（每行一个）")
    g.SetFont("s9 c222222", "Microsoft YaHei UI")
    editTitle := g.AddEdit("vTitleList Multi WantReturn w420 r7 BackgroundWhite", TitleArrToText(KeepTitleNeedles))

    g.SetFont("s8 c999999", "Microsoft YaHei UI")
    g.AddText("xm y+10 w420", "浏览器标题里的 AI 关键词仍按内置规则匹配，不必写在这里。")

    g.SetFont("s10 Norm c222222", "Microsoft YaHei UI")
    btnSave := g.AddButton("xm y+16 w110 h32 Default", "保存")
    btnCancel := g.AddButton("x+12 w110 h32", "取消")
    btnSave.OnEvent("Click", SaveSettingsClick)
    btnCancel.OnEvent("Click", CloseSettings)
    g.OnEvent("Close", OnSettingsClosed)
    g.OnEvent("Escape", CloseSettings)

    settingsGui := g
    g.Show()

    ToggleEnabled(*) {
        ui.Enabled := !ui.Enabled
        PaintToggle(togEn, ui.Enabled)
    }

    ToggleFolders(*) {
        ui.CloseFolders := !ui.CloseFolders
        PaintToggle(togFolder, ui.CloseFolders)
    }

    CloseSettings(*) {
        g.Destroy()
    }

    OnSettingsClosed(*) {
        global settingsGui
        settingsGui := 0
    }

    SaveSettingsClick(*) {
        global Enabled, SecondarySlots, CloseFolders, KeepExe, KeepTitleNeedles, settingsGui
        vals := g.Submit(false)
        Enabled := !!ui.Enabled
        CloseFolders := !!ui.CloseFolders
        slotIdx := Integer(vals.Slots)
        if (slotIdx >= 1 && slotIdx <= 3)
            SecondarySlots := slotIdx + 1
        else
            SecondarySlots := 4
        KeepExe := ParseExeText(vals.ExeList)
        KeepTitleNeedles := ParseTitleText(vals.TitleList)
        if (KeepExe.Count = 0 && KeepTitleNeedles.Length = 0)
            ApplyDefaultWhitelist()
        SaveConfig()
        UpdateTrayTip()
        state := Enabled ? "已启用" : "已暂停"
        TrayTip("双屏焦点 v6.9", "设置已保存 · " state " · 副屏 " SecondarySlots " 格", "Iconi")
        SetTimer(() => TrayTip(), -2200)
        g.Destroy()
        settingsGui := 0
    }
}

A_IconTip := "双屏焦点 v6.9"
UpdateTrayTip()
Tray := A_TrayMenu
Tray.Delete()
Tray.Add("设置…", OpenSettings)
Tray.Add()
Tray.Add("立即重排", ForceLayout)
Tray.Add("刷新显示器", RefreshMonitors)
Tray.Add()
Tray.Add("退出", (*) => ExitApp())
Tray.Default := "设置…"

startMsg := Enabled ? "已启用" : "已暂停"
TrayTip("双屏焦点 v6.9", startMsg " · 右键托盘打开设置", "Iconi")
SetTimer(() => TrayTip(), -2800)


; 点选 / 切换到哔哩哔哩时也立刻钉回副屏
sideEventCb := 0
sideEventHook := 0

InstallSidePreferHook() {
    global sideEventCb, sideEventHook
    if sideEventHook
        return
    sideEventCb := CallbackCreate(OnSidePreferWinEvent)
    sideEventHook := DllCall("user32\SetWinEventHook"
        , "UInt", 0x0003, "UInt", 0x0003
        , "Ptr", 0, "Ptr", sideEventCb
        , "UInt", 0, "UInt", 0
        , "UInt", 0x0002, "Ptr")
}

UninstallSidePreferHook(*) {
    global sideEventHook, sideEventCb
    if sideEventHook {
        DllCall("user32\UnhookWinEvent", "Ptr", sideEventHook)
        sideEventHook := 0
    }
    if sideEventCb {
        CallbackFree(sideEventCb)
        sideEventCb := 0
    }
}

OnSidePreferWinEvent(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
    global Enabled, hasDual, layoutBusy
    if (event != 0x0003 || !hwnd || idObject)
        return
    if !Enabled || !hasDual || layoutBusy
        return
    if !IsSidePrefer(hwnd)
        return
    SetTimer(LayoutSidePreferActive, -80)
}

LayoutSidePreferActive() {
    hwnd := WinExist("A")
    if hwnd && IsSidePrefer(hwnd)
        DoLayout(hwnd)
}

OnExit(UninstallSidePreferHook)
InstallSidePreferHook()
