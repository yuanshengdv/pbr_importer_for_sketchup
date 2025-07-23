# pbr_importer.rb
# Copyright (c) 2025 DistantVoices
# =============================更新说明=============================
#  0.1.0: 2025年7月22日
#         简单实现多选pbr材质贴图导入su功能
#         可以自定义关键字

require 'sketchup.rb'
require 'extensions.rb'

module DistantVoices
  module PBR_importer

    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new('pbr importer', 'pbr_importer/main')
      ex.description = '为su材质实现多选pbr贴图，然后一次性导入新建材质的功能'
      ex.version     = "0.1.0"
      ex.copyright   = 'Copyright (c) 2025 DistantVoices.'
      ex.creator     = 'DistantVoices'
      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end

  end
end