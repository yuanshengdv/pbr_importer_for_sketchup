require 'json'
require 'base64'

module DistantVoices
  module PBR_importer

    #检测sketchup版本，如果版本过低，则不加载插件
    def self.check_sketchup_version
      if  Sketchup.version.to_i < 25
        UI.messagebox("该插件为Sketchup2025创建，在旧版本中无法运行，请升级Sketchup")
        return false
      else
        return true
      end
    end

    #创建材质
    def self.create_material(name, texture, metalness, roughness, normal, ao)
      model = Sketchup.active_model
      material = model.materials.add(name)
      #设置颜色贴图
      material.texture = texture
      #设置金属度贴图
      # material.metalness_enabled = true
      material.metallic_texture = metalness
      material.metallic_factor = 1.0
      #设置粗糙度贴图
      # material.roughness_enabled = true
      material.roughness_texture = roughness
      material.roughness_factor = 1.0
      #设置法线贴图
      # material.normal_enabled = true
      material.normal_texture = normal
      material.normal_scale = 1.0
      #设置ao贴图
      # material.ao_enabled = true
      material.ao_texture = ao
      material.ao_strength = 1.0

      #选择到创建的材质
      materials = Sketchup.active_model.materials
      materials.current = material
    end

    # 读取 keywords.json 文件并转换为 Ruby 哈希表
    def self.load_keyword_mapping
      keywords_path = File.join(__dir__, 'keywords.json')

      if File.exist?(keywords_path)
        begin
          file_data = File.read(keywords_path)
          mapping = JSON.parse(file_data)

          # ✅ 返回 Ruby 哈希表
          # 示例：{"颜色"=>["albedo", "basecolor"], "金属度"=>["metallic"]}
          return mapping
        rescue JSON::ParserError => e
          UI.messagebox("keywords.json 文件格式错误：#{e.message}")
          return nil
        end
      else
        UI.messagebox("keywords.json 文件不存在")
        return nil
      end
    end

    #pbr贴图导入器
    def self.select_image_files
      #先删除缓存目录中的文件
      cache_dir = File.join(__dir__, 'temp')
      Dir["#{cache_dir}/*"].each do |item|
        File.delete(item) if File.file?(item)
      end

      html_path = File.join(__dir__, 'html', "PBRimporter.html")
      pbr_import = UI::HtmlDialog.new({
                                        dialog_title: "PBR贴图导入器",
                                        preferences_key: "com.DistantVoices.pbr_importer",
                                        scrollable: false,
                                        width: 450,
                                        height: 400,
                                        style: UI::HtmlDialog::STYLE_DIALOG
                                      })

      # 显示 HTML 页面
      pbr_import.set_file(html_path)
      pbr_import.show

      # 导入文件回调，触发图片数据写入缓存文件夹，实际的创建材质逻辑会在写入完成后，由html自动触发
      pbr_import.add_action_callback("import_pbr") do |action_context, data|
        write_temp(data)
        #pbr_import.close 不关闭窗口，方便多次导入
      end

      # 添加 create_materials 回调函数
      pbr_import.add_action_callback("create_materials") do |context|
        process_and_create_materials(pbr_import)
      end
    end

    # 处理缓存目录中的贴图并创建材质
    def self.process_and_create_materials(dialog)
      cache_dir = File.join(__dir__, 'temp')

      # 1.获取缓存目录下的所有贴图文件
      image_files = Dir["#{cache_dir}/*.{bmp,jpg,jpeg,png,psd,tif,tga}"]

      if image_files.empty?
        UI.messagebox("未找到贴图文件")
        return
      end

      # 2.读取关键词映射
      keyword_mapping = load_keyword_mapping
      unless keyword_mapping
        UI.messagebox("无法加载关键词映射，请检查 keywords.json 文件")
        return
      end

      # 3.匹配关键词并分组（忽略大小写）
      matched_files = {} # key: channel, value: [file1, file2, ...]
      unmatched_files = []

      image_files.each do |file|
        filename = File.basename(file, ".*").downcase

        matched = false
        keyword_mapping.each do |channel, keywords|
          keywords.each do |keyword|
            if filename.include?(keyword.downcase)
              matched_files[channel] ||= []
              prefix = filename.split(keyword.downcase).first.strip
              matched_files[channel] << { file: file, prefix: prefix }
              matched = true
              break
            end
          end
        end

        unless matched
          unmatched_files << file
        end
      end

      # 4.按前缀分组
      grouped_by_prefix = Hash.new { |h, k| h[k] = {} }

      matched_files.each do |channel, files|
        files.each do |file_info|
          prefix = file_info[:prefix]
          grouped_by_prefix[prefix][channel] = file_info[:file]
        end
      end

      # 5.创建材质
      success_count = 0
      failure_list = []

      grouped_by_prefix.each do |prefix, files|
        color = files["漫反射"]
        metalness = files["金属度"]
        roughness = files["粗糙度"]
        normal = files["法线"]
        ao = files["AO"]

        next if color.nil? # 至少需要颜色贴图

        begin
          create_material(
            prefix,
            color,
            metalness,
            roughness,
            normal,
            ao
          )
          success_count += 1
        rescue => e
          failure_list << "材质 '#{prefix}' 创建失败：#{e.message}"
        end
      end

      # 6.显示统计信息
      unmatched_count = unmatched_files.size

      failure_message = if failure_list.empty?
                          ""
                        else
                          "\n\n❌ 创建失败的材质：\n" + failure_list.join("\n")
                        end

      UI.messagebox("✅ 成功创建 #{success_count} 个材质\n❌ 未能匹配的贴图文件：#{unmatched_count} 个#{failure_message}")

      # 7.删除缓存文件，用于未关闭窗口的情况下二次导入
      Dir["#{cache_dir}/*"].each do |item|
        File.delete(item) if File.file?(item)
      end
    end

    # 关键字编辑器
    def self.edit_keywords
      html_path = File.join(__dir__, 'html', "keyword.html")
      dialog = UI::HtmlDialog.new({
        dialog_title: "关键词映射编辑器",
        preferences_key: "com.DistantVoices.pbr_importer.keyword",
        scrollable: true,
        width: 450,
        height: 600,
        style: UI::HtmlDialog::STYLE_DIALOG
      })

      dialog.set_file(html_path)
      dialog.show

      keywords_path = File.join(__dir__, 'keywords.json')

      # 1.读取哈希表文件
      if File.exist?(keywords_path)
        data = File.read(keywords_path)
        dialog.execute_script("receiveMapping(#{data.to_json})")
      end

      # 2.保存回调
      dialog.add_action_callback("save_mapping") do |context, data|
        File.open(keywords_path, "w") do |f|
          f.write(data)
        end
        UI.messagebox("关键词映射已保存")
      end

      # 3.加载哈希数据
      dialog.add_action_callback("load_mapping") do |context|
        if File.exist?(keywords_path)
          data = File.read(keywords_path)
          dialog.execute_script("receiveMapping(#{data.to_json})")
        else
          dialog.execute_script("receiveMapping({})")
        end
      end

      # 充值关键字按钮回调
      dialog.add_action_callback("reset_mapping") do |context|
        default_path = File.join(__dir__, 'default.json')
        keywords_path = File.join(__dir__, 'keywords.json')

        # 重置关键词
        result = UI.messagebox("确定要重置为默认关键词吗？", MB_YESNO)

        if result == IDYES
          if File.exist?(default_path)
            FileUtils.cp(default_path, keywords_path)
            UI.messagebox("关键词已重置为默认值")
            dialog.execute_script("location.reload()")
          else
            UI.messagebox("default.json 文件不存在，无法重置")
          end
        end
      end

    end

    # 写入缓存文件(su的api只能选择单文件，html又由于安全机制无法获取完整路径，只能通过写入缓存目录解决了)
    def self.write_temp(data)
      decoded = JSON.parse(data)
      filename = decoded["filename"]
      content = decoded["content"]

      # 构建完整路径并写入文件
      cache_dir = File.join(__dir__, 'temp')
      cache_path = File.join(cache_dir, filename)
      File.open(cache_path, "wb") do |f|
        f.write(Base64.decode64(content))
      end
      #puts "文件已保存至：#{cache_path}"
    end

    unless file_loaded?(__FILE__)
      main_menu = UI.menu("Plugins").add_submenu("pbr导入器")
      # 在子菜单中添加子按钮
      main_menu.add_item("导入文件") {
        select_image_files if check_sketchup_version
      }
      main_menu.add_item("pbr关键字编辑器") {
        edit_keywords if check_sketchup_version
      }
    end

  end
end