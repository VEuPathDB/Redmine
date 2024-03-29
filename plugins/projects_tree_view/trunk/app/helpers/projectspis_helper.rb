# redMine - project management software
# Copyright (C) 2006  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

module ProjectspisHelper
  include ApplicationHelper

  def issue_list(issues, &block)
    ancestors = []
    issues.each do |issue|
      while (ancestors.any? && !issue.is_descendant_of?(ancestors.last))
        ancestors.pop
      end
      yield issue, ancestors.size
      ancestors << issue unless issue.leaf?
    end
  end

  # Renders a HTML/CSS tooltip
  #
  # To use, a trigger div is needed.  This is a div with the class of "tooltip"
  # that contains this method wrapped in a span with the class of "tip"
  #
  #    <div class="tooltip"><%= link_to_issue(issue) %>
  #      <span class="tip"><%= render_issue_tooltip(issue) %></span>
  #    </div>
  #
  def render_issue_tooltip(issue)
    @cached_label_status ||= l(:field_status)
    @cached_label_start_date ||= l(:field_start_date)
    @cached_label_due_date ||= l(:field_due_date)
    @cached_label_assigned_to ||= l(:field_assigned_to)
    @cached_label_priority ||= l(:field_priority)
    
    link_to_issue(issue) + "<br /><br />" +
      "<strong>#{@cached_label_status}</strong>: #{issue.status.name}<br />" +
      "<strong>#{@cached_label_start_date}</strong>: #{format_date(issue.start_date)}<br />" +
      "<strong>#{@cached_label_due_date}</strong>: #{format_date(issue.due_date)}<br />" +
      "<strong>#{@cached_label_assigned_to}</strong>: #{issue.assigned_to}<br />" +
      "<strong>#{@cached_label_priority}</strong>: #{issue.priority.name}"
  end
    
  def render_issue_subject_with_tree(issue)
    s = ''
    issue.ancestors.each do |ancestor|
      s << '<div>' + content_tag('p', link_to_issue(ancestor))
    end
    s << '<div>' + content_tag('h3', h(issue.subject))
    s << '</div>' * (issue.ancestors.size + 1)
    s
  end
  
  def render_descendants_tree(issue)
    s = '<form><table class="list issues">'
    issue_list(issue.descendants.sort_by(&:lft)) do |child, level|
      s << content_tag('tr',
             content_tag('td', check_box_tag("ids[]", child.id, false, :id => nil), :class => 'checkbox') +
             content_tag('td', link_to_issue(child, :truncate => 60), :class => 'subject') +
             content_tag('td', h(child.status)) +
             content_tag('td', link_to_user(child.assigned_to)) +
             content_tag('td', progress_bar(child.done_ratio, :width => '80px')),
             :class => "issue issue-#{child.id} hascontextmenu #{level > 0 ? "idnt idnt-#{level}" : nil}")
    end
    s << '</form></table>'
    s
  end
  
  def render_custom_fields_rows(issue)
    return if issue.custom_field_values.empty?
    ordered_values = []
    half = (issue.custom_field_values.size / 2.0).ceil
    half.times do |i|
      ordered_values << issue.custom_field_values[i]
      ordered_values << issue.custom_field_values[i + half]
    end
    s = "<tr>\n"
    n = 0
    ordered_values.compact.each do |value|
      s << "</tr>\n<tr>\n" if n > 0 && (n % 2) == 0
      s << "\t<th>#{ h(value.custom_field.name) }:</th><td>#{ simple_format_without_paragraph(h(show_value(value))) }</td>\n"
      n += 1
    end
    s << "</tr>\n"
    s
  end
  
  def sidebar_queries
    unless @sidebar_queries
      # User can see public queries and his own queries
      visible = ARCondition.new(["is_public = ? OR user_id = ?", true, (User.current.logged? ? User.current.id : 0)])
      # Project specific queries and global queries
      visible << (@project.nil? ? ["project_id IS NULL"] : ["project_id IS NULL OR project_id = ?", @project.id])
      @sidebar_queries = Query.find(:all, 
                                    :select => 'id, name',
                                    :order => "name ASC",
                                    :conditions => visible.conditions)
    end
    @sidebar_queries
  end

  def show_detail(detail, no_html=false)
    case detail.property
    when 'attr'
      field = detail.prop_key.to_s.gsub(/\_id$/, "")
      label = l(("field_" + field).to_sym)
      case
      when ['due_date', 'start_date'].include?(detail.prop_key)
        value = format_date(detail.value.to_date) if detail.value
        old_value = format_date(detail.old_value.to_date) if detail.old_value

      when ['project_id', 'status_id', 'tracker_id', 'assigned_to_id', 'priority_id', 'category_id', 'fixed_version_id'].include?(detail.prop_key)
        value = find_name_by_reflection(field, detail.value)
        old_value = find_name_by_reflection(field, detail.old_value)

      when detail.prop_key == 'estimated_hours'
        value = "%0.02f" % detail.value.to_f unless detail.value.blank?
        old_value = "%0.02f" % detail.old_value.to_f unless detail.old_value.blank?

      when detail.prop_key == 'parent_id'
        label = l(:field_parent_issue)
        value = "##{detail.value}" unless detail.value.blank?
        old_value = "##{detail.old_value}" unless detail.old_value.blank?
      end
    when 'cf'
      custom_field = CustomField.find_by_id(detail.prop_key)
      if custom_field
        label = custom_field.name
        value = format_value(detail.value, custom_field.field_format) if detail.value
        old_value = format_value(detail.old_value, custom_field.field_format) if detail.old_value
      end
    when 'attachment'
      label = l(:label_attachment)
    end
    call_hook(:helper_issues_show_detail_after_setting, {:detail => detail, :label => label, :value => value, :old_value => old_value })

    label ||= detail.prop_key
    value ||= detail.value
    old_value ||= detail.old_value
    
    unless no_html
      label = content_tag('strong', label)
      old_value = content_tag("i", h(old_value)) if detail.old_value
      old_value = content_tag("strike", old_value) if detail.old_value and (!detail.value or detail.value.empty?)
      if detail.property == 'attachment' && !value.blank? && a = Attachment.find_by_id(detail.prop_key)
        # Link to the attachment if it has not been removed
        value = link_to_attachment(a)
      else
        value = content_tag("i", h(value)) if value
      end
    end
    
    if !detail.value.blank?
      case detail.property
      when 'attr', 'cf'
        if !detail.old_value.blank?
          l(:text_journal_changed, :label => label, :old => old_value, :new => value)
        else
          l(:text_journal_set_to, :label => label, :value => value)
        end
      when 'attachment'
        l(:text_journal_added, :label => label, :value => value)
      end
    else
      l(:text_journal_deleted, :label => label, :old => old_value)
    end
  end

  # Find the name of an associated record stored in the field attribute
  def find_name_by_reflection(field, id)
    association = Issue.reflect_on_association(field.to_sym)
    if association
      record = association.class_name.constantize.find_by_id(id)
      return record.name if record
    end
  end
  
  def projects_to_csv(projects)
    ic = Iconv.new(l(:general_csv_encoding), 'UTF-8')    
    decimal_separator = l(:general_csv_decimal_separator)
    export = FCSV.generate(:col_sep => l(:general_csv_separator)) do |csv|
      # csv header fields
      headers = [ "#",
                  "description",
                  "created_on",
                  "updated_on"
                  ]
      # Export project custom fields if project is given
      # otherwise export custom fields marked as "For all projects"
      #custom_fields = project.nil? ? IssueCustomField.for_all : project.all_issue_custom_fields
      #custom_fields.each {|f| headers << f.name}
      # Description in the last column
      headers << l(:field_description)
      csv << headers.collect {|c| begin; ic.iconv(c.to_s); rescue; c.to_s; end }
      # csv lines
      projects.each do |project|
        fields = [project.id,
                  project.description,
                  format_time(project.created_on),  
                  format_time(project.updated_on)
                  ]
        #custom_fields.each {|f| fields << show_value(issue.custom_value_for(f)) }
        #fields << issue.description
        csv << fields.collect {|c| begin; ic.iconv(c.to_s); rescue; c.to_s; end }
      end
    end
    export
  end

  def gantt_zoom_link(gantt, in_or_out)
    img_attributes = {:style => 'height:1.4em; width:1.4em; margin-left: 3px;'} # em for accessibility

    case in_or_out
    when :in
      if gantt.zoom < 4
        link_to_remote(l(:text_zoom_in) + image_tag('zoom_in.png', img_attributes.merge(:alt => l(:text_zoom_in))),
                       {:url => gantt.params.merge(:zoom => (gantt.zoom+1)), :update => 'content'},
                       {:href => url_for(gantt.params.merge(:zoom => (gantt.zoom+1)))})
      else
        l(:text_zoom_in) +
          image_tag('zoom_in_g.png', img_attributes.merge(:alt => l(:text_zoom_in)))
      end
      
    when :out
      if gantt.zoom > 1
        link_to_remote(l(:text_zoom_out) + image_tag('zoom_out.png', img_attributes.merge(:alt => l(:text_zoom_out))),
                       {:url => gantt.params.merge(:zoom => (gantt.zoom-1)), :update => 'content'},
                       {:href => url_for(gantt.params.merge(:zoom => (gantt.zoom-1)))})
      else
        l(:text_zoom_out) +
          image_tag('zoom_out_g.png', img_attributes.merge(:alt => l(:text_zoom_out)))
      end
    end
  end
end
