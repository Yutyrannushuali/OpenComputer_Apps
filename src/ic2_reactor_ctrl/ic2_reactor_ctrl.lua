local component = require("component")
local term = require("term")
local sides = require("sides")
local keyboard = require("keyboard")
local gpu = component.gpu
local reactor = component.reactor_chamber
local transposer = component.transposer
local redstone = component.redstone




-- 位置关系配置
local rs_side = 2  -- 红石信号输出方向，必须用数字表示
local rc_side = sides.west  -- 反应堆所在方向
local src_side = sides.south -- 资源箱所在方向
local bin_side = sides.north -- 垃圾箱所在方向

-- 反应堆温度百分比上限(0~1)
local heat_rate_limit = 0.5
-- 反应堆重启温度(0~1)，反应堆达到此温度后重启
local restart_rate = 0.4

-- 判断是否在冷却状态
local isCooling = false

-- 快捷键列表
local cmd_list = '退出: [Ctrl+C] 开始: [Ctrl+R] 暂停: [Ctrl+S]'
-- 控制程序是否运行
local isRun = false
-- 反应堆总槽位数，资源箱总槽位数，垃圾箱总槽位数
local reactor_size, src_size, bin_size = transposer.getInventorySize(rc_side) - 4, transposer.getInventorySize(src_side), transposer.getInventorySize(bin_side)
-- 列数
local col_num = reactor_size/6
-- 耐久耗尽才废弃的组件
local item_list = {
    'ic2:uranium_fuel_rod',
    'ic2:dual_uranium_fuel_rod',
    'ic2:quad_uranium_fuel_rod',
    'ic2:mox_fuel_rod',
    'ic2:dual_mox_fuel_rod',
    'ic2:quad_mox_fuel_rod',
}
-- 不会损坏的组件
local special_item_list = {
    'ic2:component_heat_vent',
    'ic2:plating',
    'ic2:heat_plating',
    'ic2:containment_plating',
    'ic2:iridium_reflector'
}




-- 查询元素是否在表中
local function IsInTable(value, table)
    local found = false
    for i, v in ipairs(table) do
        if v == value then
            found = true
            break
        end
    end
    return found
end

-- 查询指定方向容器中指定槽位
local function SlotInfo(side, slot)
    local slot_info = transposer.getStackInSlot(side, slot)
    return slot_info
end

-- 更换组件
local function change(item_info, item_slot)
    -- 将反应堆的物品放入垃圾箱
    for bin_slot = 1, bin_size do
        if transposer.transferItem(rc_side, bin_side, 1, item_slot, bin_slot) == 1 then
            break
        end
    end
    -- 将资源箱的物品放入反应堆
    for src_slot = 1, src_size do
        -- 槽位不为空
        if SlotInfo(src_side, src_slot) then
            if SlotInfo(src_side, src_slot)['name'] == item_info then
                transposer.transferItem(src_side, rc_side, 1, src_slot, item_slot)
                break
            end
        end
    end
    -- 关闭各个方向的红石信号输出
    for i = 0, 5 do
        redstone.setOutput(i, 0)
    end
    print('资源箱中缺少必要组件，请补充完毕后重启程序！')
    os.exit(0)
end

-- 定义各物品名称，x为transposer.getStackInSlot(side:number, slot:number):table的返回值
local function item(x)
    local y = ''
    if x['name'] == 'ic2:heat_vent' then
       y = 'h v'
    elseif x['name'] == 'ic2:reactor_heat_vent' then
        y = 'rhv'
    elseif x['name'] == 'ic2:overclocked_heat_vent' then
        y = 'ohv'
    elseif x['name'] == 'ic2:advanced_heat_vent' then
        y = 'ahv'
    elseif x['name'] == 'ic2:component_heat_vent' then
        y = 'chv'
    elseif x['name'] == 'ic2:heat_exchanger' then
        y = 'h e'
    elseif x['name'] == 'ic2:reactor_heat_exchanger' then
        y = 'rhe'
    elseif x['name'] == 'ic2:component_heat_exchanger' then
        y = 'che'
    elseif x['name'] == 'ic2:advanced_heat_exchanger' then
        y = 'ahe'
    elseif x['name'] == 'ic2:plating' then
        y = ' p '
    elseif x['name'] == 'ic2:heat_plating' then
        y = 'h p'
    elseif x['name'] == 'ic2:containment_plating' then
        y = 'c p'
    elseif x['name'] == 'ic2:neutron_reflector' then
        y = 'n r'
    elseif x['name'] == 'ic2:thick_neutron_reflector' then
        y = 'tnr'
    elseif x['name'] == 'ic2:iridium_reflector' then
        y = 'i r'
    elseif x['name'] == 'ic2:uranium_fuel_rod' then
        y = 'u f'
    elseif x['name'] == 'ic2:dual_uranium_fuel_rod' then
        y = 'duf'
    elseif x['name'] == 'ic2:quad_uranium_fuel_rod' then
        y = 'quf'
    elseif x['name'] == 'ic2:mox_fuel_rod' then
        y = 'm f'
    elseif x['name'] == 'ic2:dual_mox_fuel_rod' then
        y = 'dmf'
    elseif x['name'] == 'ic2:quad_mox_fuel_rod' then
        y = 'qmf'
    else
        y = 'OUT'
    end
    return y
end

-- 反应堆温度监视器，参数side为输出红石信号的方向，heat为反应堆温度上限
local function heat_monitor(side, heat_rate)
    -- 获取温度数据
    local now_heat = reactor.getHeat()
    local max_heat = reactor.getMaxHeat()
    local now_heat_rate = now_heat/max_heat
    -- 如果控制程序正在运行
    if isRun then
        -- 如果在冷却状态
        if isCooling then
            -- 温度百分比低于上限的10%则开启反应堆
            if now_heat_rate < restart_rate then
                redstone.setOutput(side, 15)
                isCooling = false
            end
        -- 如果不在冷却状态
        else
            -- 温度百分比超过上限则关闭反应堆
            if now_heat_rate > heat_rate then
                redstone.setOutput(side, 0)
                isCooling = true
            end
        end
    end
    -- 返回值为当前温度数值，当前温度百分比
    return now_heat, now_heat_rate
end

-- 反应堆指定槽位组件监视器，slot为虚监视的槽位
local function item_monitor(slot)
    -- 初始化数据
    local damage = 0
    local item_name = '   '
    -- 获取槽位信息
    local slot_info = SlotInfo(rc_side, slot)
    -- 判断槽位是否为空
    if slot_info ~= nil then
        -- 获取组件名称
        item_name = item(slot_info)
            -- 计算已损失耐久
            if IsInTable(slot_info['name'], special_item_list) then
                -- 不会损坏的组件
                damage = -1
            else
                -- 会损坏的组件
                if slot_info['damage'] >= slot_info['maxDamage'] then
                    damage = 1
                else
                    damage = slot_info['damage']/slot_info['maxDamage']
                end
            end
        -- 如果控制程序正在运行
        if isRun then
            -- 判断是否要更换
            if IsInTable(slot_info['name'], item_list) then
                -- 在item_list中的组件，耐久值耗尽才更换
                if damage >= 1 and slot_info['damage'] ~= 0 then
                    change(slot_info['name'], slot)
                end
            else
                -- 不在item_list中的组件，耐久值消耗90%才更换
                if damage >= 0.9 and slot_info['damage'] ~= 0 then
                    change(slot_info['name'], slot)
                end
            end
        end
    end
    return damage, item_name
end


-- 反应堆能量监视器
local function EU_monitor()
    local EU = reactor.getReactorEUOutput()
    return EU
end

-- 组件监视器GUI，显示在第1~6行
local function item_gui()
    local col_cnt = 1
    local row_cnt = 1
    for i = 1, reactor_size do
        local damage, item_name = item_monitor(i)
        -- 显示名称
        gpu.set(2+(col_cnt-1)*5, row_cnt*2-1, '⌈'..item_name..'⌉')
        -- 显示耐久
        if item_name == '   ' or damage == -1 then
            gpu.set(2+(col_cnt-1)*5, row_cnt*2, '⌊'..'   '..'⌋')
        else
            gpu.set(2+(col_cnt-1)*5, row_cnt*2, '⌊'..string.format('%.1f', 1-damage)..'⌋')
        end
        col_cnt = col_cnt + 1
        if col_cnt > col_num then
            col_cnt = 1
            row_cnt = row_cnt + 1
        end
    end
end

-- 温度监视器GUI，显示在7，8行
local function heat_gui()
    local heat, heat_rate = heat_monitor(rs_side, heat_rate_limit)
    -- 格式化温度数据
    local heat_str = ''
    if heat > 10^9 then
        heat_str = string.format('%11s', string.format('%.0f', heat/(10^9)) .. 'B')
    elseif heat > 10^6 then
        heat_str = string.format('%11s', string.format('%.0f', heat/(10^6)) .. 'M')
    elseif heat > 10^3 then
        heat_str = string.format('%11s', string.format('%.0f', heat/(10^3)) .. 'K')
    else
        heat_str = string.format('%11s', string.format('%.0f', heat))
    end
    -- 格式化温度比例数据
    local heat_rate_str = string.format('%8s', string.format('%.2f', heat_rate*100) .. '%')
    -- 清理屏幕
    gpu.fill(2, 13, 15, 1, ' ')
    gpu.fill(2, 14, 15, 1, ' ')
    -- 输出到屏幕
    gpu.set(2, 13, '温度:' .. heat_str)
    gpu.set(2, 14, '温度(%):' .. heat_rate_str)
end

-- 其他数据GUI，显示在第7、8行
local function other_gui()
    local EU = EU_monitor()
    gpu.set(22, 13, string.format('输出: ' .. string.format('%.2f', EU) .. 'EU/t'))
    if isCooling then
        gpu.set(22, 14, string.format('Cooling!'))
    end
    if reactor.producesEnergy() then
        gpu.set(22, 15, '反应堆: 运行')
    else
        gpu.set(22, 15, '反应堆: 停止')
    end
    if isRun then
        gpu.set(2, 15, '控制程序: 运行')
    else
        gpu.set(2, 15, '控制程序: 停止')
    end
end




-- 设置分辨率为50x16
gpu.setResolution(50, 16)
-- 清空屏幕
term.clear()
-- 在最后一行显示快捷键
term.setCursor(1, 16)
term.write(cmd_list)


while true do
    -- 确保控制程序未运行时不会输出红石信号
    if not(isRun) then
        for i = 0, 5 do
            redstone.setOutput(i, 0)
        end
    end
    item_gui()
    heat_gui()
    other_gui()
    -- 判断按了哪些键
    local isCtrl = keyboard.isControlDown()
    local isC, isR, isS = keyboard.isKeyDown(46), keyboard.isKeyDown(19), keyboard.isKeyDown(31)
    -- Ctrl+C为“退出”
    if isCtrl and isC then
        break
    -- Ctrl+R为“运行控制程序”
    elseif isCtrl and isR then
        redstone.setOutput(rs_side, 15)
        isRun = true
    -- Ctrl+S为“暂停控制程序”
    elseif isCtrl and isS then
        redstone.setOutput(rs_side, 0)
        isRun = false
    end
    os.sleep(0)
end

-- 关闭各个方向的红石信号输出
for i = 0, 5 do
    redstone.setOutput(i, 0)
end